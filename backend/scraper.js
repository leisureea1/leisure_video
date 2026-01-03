const axios = require('axios');
const cheerio = require('cheerio');

const HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
    "Referer": "https://ccios.cc/"
};

const BASE_URL = "https://ccios.cc";

// 请求超时设置
const REQUEST_TIMEOUT = 8000;

// 创建 axios 实例，统一配置
const httpClient = axios.create({
    headers: HEADERS,
    timeout: REQUEST_TIMEOUT,
    maxRedirects: 5
});

async function fetchHtml(url) {
    const target = absoluteUrl(url);
    const res = await httpClient.get(target);
    return { html: res.data, finalUrl: target };
}

function extractVideoUrlFromHtml(html) {
    const jsonMatch = html.match(/var player_aaaa\s*=\s*({.*?})<\/script>/s) ||
                      html.match(/var player_aaaa\s*=\s*({.*?});/s);

    let videoUrl = null;

    if (jsonMatch) {
        try {
            const jsonStr = jsonMatch[1];
            const data = JSON.parse(jsonStr);
            videoUrl = data.url;
        } catch (e) {
            console.error("JSON Parse Error", e);
        }
    }

    if (!videoUrl) {
        const urlMatch = html.match(/"url":"(.*?)"/);
        if (urlMatch) {
            videoUrl = urlMatch[1].replace(/\\/g, '');
        }
    }

    return videoUrl;
}

function parseSourceLinks(html, playUrl) {
    const $ = cheerio.load(html);
    const sources = [];
    const seen = new Set();

    $('.xianlu a').each((_, el) => {
        const $link = $(el);
        const clone = $link.clone();
        clone.find('small').remove();
        const name = clone.text().trim() || '备用线路';
        let href = $link.attr('href') || '';
        const isActive = $link.hasClass('active') || href === 'javascript:;' || !href;
        if (!href || href === 'javascript:;') {
            href = playUrl;
        }
        const pageUrl = absoluteUrl(href);
        if (!pageUrl) return;
        if (seen.has(pageUrl)) return;
        seen.add(pageUrl);
        sources.push({
            name,
            pageUrl,
            isActive
        });
    });

    if (!sources.length) {
        sources.push({
            name: '默认线路',
            pageUrl: absoluteUrl(playUrl),
            isActive: true
        });
    }

    return sources;
}

/**
 * 解析 m3u8 内容，处理相对路径
 */
async function resolveM3u8(url) {
    try {
        const res = await httpClient.get(url);
        const content = res.data;
        
        if (!content.includes('#EXTM3U')) {
            return url;
        }
        
        const lines = content.split('\n');
        let candidate = null;

        for (let i = 0; i < lines.length - 1; i++) {
            const line = lines[i].trim();
            const nextLine = lines[i + 1].trim();
            if (line.startsWith('#EXT-X-STREAM-INF') && nextLine && !nextLine.startsWith('#')) {
                if (nextLine.includes('.m3u8') || !nextLine.includes('.ts')) {
                    candidate = nextLine;
                    break;
                }
            }
        }

        if (!candidate) {
            for (let i = lines.length - 1; i >= 0; i--) {
                const line = lines[i].trim();
                if (line && !line.startsWith('#') && line.includes('.m3u8')) {
                    candidate = line;
                    break;
                }
            }
        }

        if (!candidate) {
            const hasTs = lines.some(l => l.trim().endsWith('.ts') || l.includes('.ts?'));
            if (hasTs) {
                return url;
            }
            return url;
        }

        if (candidate.startsWith('http')) {
            return candidate;
        }
        
        const urlObj = new URL(url);
        if (candidate.startsWith('/')) {
            return `${urlObj.protocol}//${urlObj.host}${candidate}`;
        } else {
            const basePath = url.substring(0, url.lastIndexOf('/'));
            return `${basePath}/${candidate}`;
        }
    } catch (e) {
        console.error("解析 m3u8 失败:", e.message);
        return url;
    }
}

/**
 * 获取播放页的视频地址 - 优化版：并行请求多线路
 */
async function getVideoUrlFromPlayPage(playUrl) {
    try {
        const { html, finalUrl } = await fetchHtml(playUrl);
        const sourceLinks = parseSourceLinks(html, finalUrl);
        
        // 🚀 优化：并行处理所有线路
        const resolveSource = async (source) => {
            try {
                let pageHtml = html;
                if (source.pageUrl !== finalUrl) {
                    const fetched = await fetchHtml(source.pageUrl);
                    pageHtml = fetched.html;
                }

                const rawUrl = extractVideoUrlFromHtml(pageHtml);
                let streamUrl = rawUrl;
                if (streamUrl && streamUrl.endsWith('.m3u8')) {
                    streamUrl = await resolveM3u8(streamUrl);
                }

                return {
                    name: source.name,
                    pageUrl: source.pageUrl,
                    isActive: source.isActive,
                    rawUrl,
                    streamUrl
                };
            } catch (e) {
                return {
                    name: source.name,
                    pageUrl: source.pageUrl,
                    isActive: source.isActive,
                    rawUrl: null,
                    streamUrl: null
                };
            }
        };

        // 并行解析所有线路
        const resolvedSources = await Promise.all(sourceLinks.map(resolveSource));

        const primary = resolvedSources.find((src) => src.streamUrl && src.isActive) ||
                        resolvedSources.find((src) => src.streamUrl) ||
                        null;

        return {
            url: primary ? primary.streamUrl : null,
            sources: resolvedSources
        };
    } catch (e) {
        console.error(`获取播放页失败: ${playUrl}`, e.message);
        return { url: null, sources: [] };
    }
}

function absoluteUrl(link) {
    if (!link) return null;
    if (link.startsWith('http')) return link;
    if (link.startsWith('//')) return `https:${link}`;
    return BASE_URL + link;
}

function parseInfoFromHtml($, fallbackTitle = '') {
    const rawTitle = $('title').first().text().trim();
    let title = fallbackTitle || rawTitle;
    const bracket = rawTitle.match(/《(.+?)》/);
    if (bracket && bracket[1]) {
        title = bracket[1];
    } else if (rawTitle.includes('-')) {
        title = rawTitle.split('-')[0].trim();
    }

    const desc = $('meta[name="description"]').attr('content') || '';
    const coverMeta = $('meta[property="og:image"]').attr('content') || '';
    const keywords = $('meta[name="keywords"]').attr('content') || '';
    const tags = keywords
        .split(',')
        .map((s) => s.trim())
        .filter((s) => s && s !== '策驰影院')
        .slice(0, 8);

    return {
        title: title || fallbackTitle || '未知标题',
        cover: absoluteUrl(coverMeta),
        description: desc.replace(/\s+/g, ' ').trim(),
        tags,
        extra: []
    };
}

function parseDetailInfo($) {
    const heading = $('h1, h2, .title, .name, .vodh h2').first().text().trim();
    const cover = $('img[data-src], .lazyload, .detail-poster img, .pic img').first().attr('data-src')
        || $('img[data-original]').first().attr('data-original')
        || $('img').first().attr('src');
    const description = $('.detail-desc, .desc, .content-desc, .vod-content, .sketch, .module-info-introduction-content')
        .first()
        .text()
        .replace(/\s+/g, ' ')
        .trim();

    const tags = [];
    $('.detail-tags a, .tags a, .data a').each((_, el) => {
        const text = $(el).text().trim();
        if (text && text !== '策驰影院') tags.push(text);
    });

    const extra = [];
    $('.detail-info li, .data span, .data h4, .vodh p').each((_, el) => {
        const label = $(el).find('span, em').first().text().trim() || $(el).attr('class');
        const cloned = $(el).clone();
        cloned.children().remove();
        const value = cloned.text().trim();
        if (value) {
            extra.push({
                label: label || '信息',
                value
            });
        }
    });

    const hasMeaningfulTitle = heading && heading !== '策驰影院';
    if (!hasMeaningfulTitle) {
        return parseInfoFromHtml($, heading);
    }

    return {
        title: heading || '未知标题',
        cover: absoluteUrl(cover),
        description,
        tags: Array.from(new Set(tags)).slice(0, 8),
        extra: extra.slice(0, 6)
    };
}

const parseInfoFromPlayHtml = parseInfoFromHtml;

function parseEpisodeAnchors(html) {
    const $ = cheerio.load(html);
    const episodes = [];
    $('.jisu a').each((_, el) => {
        const link = $(el).attr('href');
        const title = $(el).text().trim();
        if (link && title) {
            episodes.push({
                name: title,
                link: absoluteUrl(link)
            });
        }
    });

    if (!episodes.length) {
        const fallbackLink = $('a[href^="/ccplay/"]').attr('href');
        if (fallbackLink) {
            episodes.push({
                name: '立即播放',
                link: absoluteUrl(fallbackLink)
            });
        }
    }

    return episodes;
}

/**
 * 解析剧集列表 - 优化版：并行请求多线路
 */
async function parseEpisodes(detailUrl) {
    try {
        let info = null;
        let detailHtml = null;
        let firstPlayLink = null;

        try {
            const fetchedDetail = await fetchHtml(detailUrl);
            detailHtml = fetchedDetail.html;
        } catch (err) {
            console.warn('detail fetch failed, will fall back to play page info', err.message);
        }

        if (detailHtml) {
            const $detail = cheerio.load(detailHtml);
            info = parseDetailInfo($detail);
            firstPlayLink = $detail('a[href^="/ccplay/"]').attr('href');
        }

        if (!firstPlayLink) {
            const guess = detailUrl.match(/(\d+)/);
            if (guess) {
                firstPlayLink = `/ccplay/${guess[1]}-1-1.html`;
            }
        }

        if (!firstPlayLink) {
            return { info, episodes: [], sources: [] };
        }

        const initialPlayUrl = absoluteUrl(firstPlayLink);
        const { html: playHtml } = await fetchHtml(initialPlayUrl);
        const sourceLinks = parseSourceLinks(playHtml, initialPlayUrl);

        // 🚀 优化：并行获取所有线路的剧集列表
        const fetchSourceEpisodes = async (source) => {
            try {
                let htmlToUse = playHtml;
                if (source.pageUrl !== initialPlayUrl) {
                    const fetched = await fetchHtml(source.pageUrl);
                    htmlToUse = fetched.html;
                }
                const episodes = parseEpisodeAnchors(htmlToUse);
                return {
                    name: source.name,
                    pageUrl: source.pageUrl,
                    episodes,
                    html: htmlToUse
                };
            } catch (e) {
                return {
                    name: source.name,
                    pageUrl: source.pageUrl,
                    episodes: [],
                    html: null
                };
            }
        };

        const sourceResults = await Promise.all(sourceLinks.map(fetchSourceEpisodes));

        // 从结果中提取 info
        if (!info) {
            const validSource = sourceResults.find(s => s.html);
            if (validSource) {
                info = parseInfoFromPlayHtml(cheerio.load(validSource.html));
            }
        }

        if (!info) {
            info = parseInfoFromPlayHtml(cheerio.load(playHtml));
        }

        const fallbackEpisodes = sourceResults.find((s) => s.episodes.length)?.episodes || [];

        // 清理返回数据，移除 html 字段
        const cleanedSources = sourceResults.map(({ name, pageUrl, episodes }) => ({
            name,
            pageUrl,
            episodes
        }));

        return { info, episodes: fallbackEpisodes, sources: cleanedSources, detailUrl: absoluteUrl(detailUrl) };
    } catch (e) {
        console.error("解析剧集列表失败", e.message);
        return { info: null, episodes: [], sources: [] };
    }
}

/**
 * 搜索功能
 */
async function search(keyword) {
    try {
        const searchUrl = `${BASE_URL}/search/-------------.html`;
        const res = await httpClient.get(searchUrl, {
            params: { wd: keyword }
        });
        
        const $ = cheerio.load(res.data);
        const results = [];
        
        $('.search-con ul li').each((i, el) => {
            const $el = $(el);
            const link = $el.find('.info p a').first().attr('href');
            const title = $el.find('.info p a').first().text().trim();
            const cover = $el.find('.pic img').attr('data-src') || $el.find('.pic img').attr('src');
            
            if (link && title) {
                results.push({
                    title,
                    cover: absoluteUrl(cover),
                    detailUrl: BASE_URL + link
                });
            }
        });
        
        return results;
    } catch (e) {
        console.error("搜索失败", e.message);
        return [];
    }
}

/**
 * 获取首页推荐
 */
async function getHomeRecommend() {
    try {
        const res = await httpClient.get(BASE_URL);
        const $ = cheerio.load(res.data);
        const sections = [];

        $('.block').each((_, blockEl) => {
            const $block = $(blockEl);
            const sectionTitle = $block.find('.a-tit h2').first().text().trim()
                || $block.find('h2').first().text().trim();
            
            if (!sectionTitle || sectionTitle.includes('公告') || sectionTitle.includes('永不')) return;

            const items = [];
            $block.find('.a-con-inner').each((_, itemEl) => {
                const $item = $(itemEl);
                const $link = $item.find('.pic a').first();
                const link = $link.attr('href');
                const title = $link.attr('title') || $item.find('.s1 a').text().trim();
                const cover = $item.find('img').attr('data-src') || $item.find('img').attr('src');
                const note = $item.find('.s4').text().trim();

                if (link && title && !title.includes('策驰')) {
                    items.push({
                        title: title.trim(),
                        cover: absoluteUrl(cover),
                        detailUrl: absoluteUrl(link),
                        note
                    });
                }
            });

            if (items.length > 0) {
                sections.push({
                    title: sectionTitle.replace(/NEW|更多.*$/g, '').trim(),
                    items: items.slice(0, 12)
                });
            }
        });

        if (sections.length === 0) {
            const items = [];
            $('a[href*="/ccvod/"]').each((_, el) => {
                const $a = $(el);
                const link = $a.attr('href');
                const title = $a.attr('title') || $a.text().trim();
                const $img = $a.find('img');
                const cover = $img.attr('data-src') || $img.attr('src');

                if (link && title && title.length > 1 && !title.includes('策驰') && cover) {
                    items.push({
                        title,
                        cover: absoluteUrl(cover),
                        detailUrl: absoluteUrl(link),
                        note: ''
                    });
                }
            });

            const seen = new Set();
            const uniqueItems = items.filter(item => {
                if (seen.has(item.detailUrl)) return false;
                seen.add(item.detailUrl);
                return true;
            });

            if (uniqueItems.length > 0) {
                sections.push({
                    title: '热门推荐',
                    items: uniqueItems.slice(0, 20)
                });
            }
        }

        return sections;
    } catch (e) {
        console.error("获取首页推荐失败", e.message);
        return [];
    }
}

/**
 * 获取分类列表
 */
async function getCategoryList(category, page = 1) {
    try {
        const validCategories = ['tv', 'movie', 'anime', 'playlet'];
        if (!validCategories.includes(category)) {
            category = 'tv';
        }
        
        const pageStr = page > 1 ? page.toString() : '';
        const url = `${BASE_URL}/cclist/${category}-----${pageStr}.html`;
        
        const res = await httpClient.get(url);
        const $ = cheerio.load(res.data);
        const items = [];

        $('.a-con-inner, .module-item, .vod-list li').each((_, el) => {
            const $item = $(el);
            const $link = $item.find('a').first();
            const link = $link.attr('href');
            const title = $link.attr('title') || $item.find('.s1 a, .video-name').text().trim() || $link.text().trim();
            const cover = $item.find('img').attr('data-src') || $item.find('img').attr('src');
            const note = $item.find('.s4, .pic-text, .video-note').text().trim();
            const rating = $item.find('.s3').text().trim();

            if (link && title && !title.includes('策驰') && title.length > 1) {
                items.push({
                    title: title.trim(),
                    cover: absoluteUrl(cover),
                    detailUrl: absoluteUrl(link),
                    note,
                    rating
                });
            }
        });

        const seen = new Set();
        const uniqueItems = items.filter(item => {
            if (seen.has(item.detailUrl)) return false;
            seen.add(item.detailUrl);
            return true;
        });

        let totalPages = 1;
        const pageLinks = $('.page-link a, .pagination a, .page a');
        pageLinks.each((_, el) => {
            const text = $(el).text().trim();
            const num = parseInt(text);
            if (!isNaN(num) && num > totalPages) {
                totalPages = num;
            }
        });
        
        pageLinks.each((_, el) => {
            const href = $(el).attr('href') || '';
            const match = href.match(/-----(\d+)\.html/);
            if (match) {
                const num = parseInt(match[1]);
                if (num > totalPages) totalPages = num;
            }
        });

        return {
            items: uniqueItems,
            page,
            totalPages,
            hasMore: page < totalPages
        };
    } catch (e) {
        console.error("获取分类列表失败", e.message);
        return { items: [], page: 1, totalPages: 1, hasMore: false };
    }
}

module.exports = {
    search,
    parseEpisodes,
    getVideoUrlFromPlayPage,
    getHomeRecommend,
    getCategoryList
};
