const express = require('express');
const cors = require('cors');
const { search, parseEpisodes, getVideoUrlFromPlayPage, getHomeRecommend, getCategoryList } = require('./scraper');
const cache = require('./cache');

const app = express();
const PORT = 8080;

app.use(cors());
app.use(express.json());

// 初始化 Redis
cache.initRedis();

// ==================== 定时任务配置 ====================
const SCHEDULER_CONFIG = {
  HOME_INTERVAL: 25 * 60 * 1000,      // 首页刷新间隔 25 分钟
  CATEGORY_INTERVAL: 12 * 60 * 1000,  // 分类刷新间隔 12 分钟
  CATEGORIES: ['tv', 'movie', 'anime', 'playlet'],
  CATEGORY_PAGES: 3,                   // 每个分类预加载前 3 页
  PREFETCH_DELAY: 500,                 // 预解析间隔，避免请求过快
};

// 主动抓取首页内容
async function fetchHomeContent() {
  console.log('📡 [定时任务] 开始抓取首页内容...');
  try {
    const cacheKey = cache.generateKey('home', 'recommend');
    const sections = await getHomeRecommend();
    
    if (sections && sections.length > 0) {
      await cache.set(cacheKey, sections, cache.TTL.HOME);
      console.log(`✅ [定时任务] 首页内容已更新，${sections.length} 个板块`);
      
      // 预解析首页热门内容的详情
      const allItems = sections.flatMap(s => s.items || []).slice(0, 15);
      for (const item of allItems) {
        if (item.detailUrl) {
          await sleep(SCHEDULER_CONFIG.PREFETCH_DELAY);
          prefetchDetail(item.detailUrl);
        }
      }
    }
  } catch (e) {
    console.error('❌ [定时任务] 首页抓取失败:', e.message);
  }
}

// 主动抓取分类内容
async function fetchCategoryContent() {
  console.log('📡 [定时任务] 开始抓取分类内容...');
  
  for (const category of SCHEDULER_CONFIG.CATEGORIES) {
    for (let page = 1; page <= SCHEDULER_CONFIG.CATEGORY_PAGES; page++) {
      try {
        const cacheKey = cache.generateKey('category', { type: category, page });
        const result = await getCategoryList(category, page);
        
        if (result && result.items && result.items.length > 0) {
          await cache.set(cacheKey, result, cache.TTL.CATEGORY);
          console.log(`✅ [定时任务] 分类 ${category} 第 ${page} 页已更新，${result.items.length} 条`);
          
          // 预解析前几个内容的详情（仅第一页）
          if (page === 1) {
            const itemsToPrefetch = result.items.slice(0, 5);
            for (const item of itemsToPrefetch) {
              if (item.detailUrl) {
                await sleep(SCHEDULER_CONFIG.PREFETCH_DELAY);
                prefetchDetail(item.detailUrl);
              }
            }
          }
        }
        
        // 请求间隔
        await sleep(300);
      } catch (e) {
        console.error(`❌ [定时任务] 分类 ${category} 第 ${page} 页抓取失败:`, e.message);
      }
    }
  }
  
  console.log('✅ [定时任务] 分类内容抓取完成');
}

// 启动定时任务
function startScheduler() {
  console.log('🕐 启动定时任务调度器...');
  
  // 服务启动后延迟 5 秒开始首次抓取，避免启动时压力过大
  setTimeout(async () => {
    await fetchHomeContent();
    await fetchCategoryContent();
  }, 5000);
  
  // 定时刷新首页
  setInterval(fetchHomeContent, SCHEDULER_CONFIG.HOME_INTERVAL);
  
  // 定时刷新分类
  setInterval(fetchCategoryContent, SCHEDULER_CONFIG.CATEGORY_INTERVAL);
  
  console.log(`📅 首页刷新间隔: ${SCHEDULER_CONFIG.HOME_INTERVAL / 60000} 分钟`);
  console.log(`📅 分类刷新间隔: ${SCHEDULER_CONFIG.CATEGORY_INTERVAL / 60000} 分钟`);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// 并发控制：限制同时进行的预解析任务数
const MAX_CONCURRENT_PREFETCH = 3;
let activePrefetchCount = 0;
const prefetchQueue = [];

async function runPrefetchTask(task) {
  while (activePrefetchCount >= MAX_CONCURRENT_PREFETCH) {
    await new Promise(resolve => prefetchQueue.push(resolve));
  }
  activePrefetchCount++;
  try {
    await task();
  } catch (e) {
    console.error('预解析任务失败:', e.message);
  } finally {
    activePrefetchCount--;
    if (prefetchQueue.length > 0) {
      const next = prefetchQueue.shift();
      next();
    }
  }
}

// 异步预解析详情页
async function prefetchDetail(detailUrl) {
  const cacheKey = cache.generateKey('detail', detailUrl);
  const cached = await cache.get(cacheKey);
  if (cached) return; // 已有缓存，跳过

  runPrefetchTask(async () => {
    console.log(`🔄 预解析详情: ${detailUrl}`);
    const detail = await parseEpisodes(detailUrl);
    if (detail && detail.episodes && detail.episodes.length > 0) {
      await cache.set(cacheKey, detail, cache.TTL.DETAIL);
      // 预解析前几集的播放地址
      const episodesToPrefetch = detail.episodes.slice(0, 3);
      for (const ep of episodesToPrefetch) {
        prefetchPlayUrl(ep.link);
      }
    }
  });
}

// 异步预解析播放地址
async function prefetchPlayUrl(playUrl) {
  const cacheKey = cache.generateKey('play', playUrl);
  const cached = await cache.get(cacheKey);
  if (cached) return; // 已有缓存，跳过

  runPrefetchTask(async () => {
    console.log(`🔄 预解析播放地址: ${playUrl}`);
    const playInfo = await getVideoUrlFromPlayPage(playUrl);
    if (playInfo && playInfo.url) {
      await cache.set(cacheKey, playInfo, cache.TTL.PLAY_URL);
    }
  });
}

// 首页推荐接口
app.get('/api/home', async (req, res) => {
  try {
    const cacheKey = cache.generateKey('home', 'recommend');
    const sections = await cache.withCache(cacheKey, cache.TTL.HOME, async () => {
      return await getHomeRecommend();
    });
    
    // 异步预解析首页推荐的详情
    if (sections && sections.length > 0) {
      const allItems = sections.flatMap(s => s.items || []).slice(0, 10);
      for (const item of allItems) {
        if (item.detailUrl) {
          prefetchDetail(item.detailUrl);
        }
      }
    }
    
    res.json({ data: sections });
  } catch (e) {
    console.error('获取首页失败:', e.message);
    res.json({ error: e.message, data: [] });
  }
});

// 分类列表接口
app.get('/api/category', async (req, res) => {
  const { type, page } = req.query;
  const categoryType = type || 'tv';
  const pageNum = parseInt(page) || 1;
  try {
    const cacheKey = cache.generateKey('category', { type: categoryType, page: pageNum });
    const result = await cache.withCache(cacheKey, cache.TTL.CATEGORY, async () => {
      return await getCategoryList(categoryType, pageNum);
    });
    
    // 异步预解析分类列表的详情（前5个）
    if (result && result.items && result.items.length > 0) {
      const itemsToPrefetch = result.items.slice(0, 5);
      for (const item of itemsToPrefetch) {
        if (item.detailUrl) {
          prefetchDetail(item.detailUrl);
        }
      }
    }
    
    res.json(result);
  } catch (e) {
    console.error('获取分类失败:', e.message);
    res.json({ error: e.message, items: [], page: 1, totalPages: 1, hasMore: false });
  }
});

// 搜索接口
app.get('/api/search', async (req, res) => {
  const { keyword } = req.query;
  if (!keyword) {
    return res.json({ error: '请输入关键词', data: [] });
  }
  try {
    const cacheKey = cache.generateKey('search', keyword);
    const results = await cache.withCache(cacheKey, cache.TTL.SEARCH, async () => {
      return await search(keyword);
    });
    
    // 🚀 关键优化：搜索结果返回后，立即异步预解析所有结果的详情和播放地址
    if (results && results.length > 0) {
      console.log(`🚀 开始预解析 ${results.length} 个搜索结果`);
      for (const item of results) {
        if (item.detailUrl) {
          prefetchDetail(item.detailUrl);
        }
      }
    }
    
    res.json({ data: results });
  } catch (e) {
    console.error('搜索失败:', e.message);
    res.json({ error: e.message, data: [] });
  }
});

// 详情接口
app.get('/api/detail', async (req, res) => {
  const { url } = req.query;
  if (!url) {
    return res.json({ error: '请提供详情URL' });
  }
  try {
    const cacheKey = cache.generateKey('detail', url);
    const detail = await cache.withCache(cacheKey, cache.TTL.DETAIL, async () => {
      return await parseEpisodes(url);
    });
    
    // 🚀 关键优化：详情返回后，立即异步预解析所有剧集的播放地址
    if (detail && detail.episodes && detail.episodes.length > 0) {
      console.log(`🚀 开始预解析 ${detail.episodes.length} 集播放地址`);
      for (const ep of detail.episodes) {
        if (ep.link) {
          prefetchPlayUrl(ep.link);
        }
      }
    }
    
    res.json(detail);
  } catch (e) {
    console.error('获取详情失败:', e.message);
    res.json({ error: e.message, info: null, episodes: [], sources: [] });
  }
});

// 播放地址接口
app.get('/api/play', async (req, res) => {
  const { url, detailUrl } = req.query;
  if (!url) {
    return res.json({ error: '请提供播放URL' });
  }
  try {
    const cacheKey = cache.generateKey('play', url);
    const playInfo = await cache.withCache(cacheKey, cache.TTL.PLAY_URL, async () => {
      return await getVideoUrlFromPlayPage(url);
    });
    
    // 🚀 自动预解析后续剧集
    if (detailUrl) {
      prefetchNextEpisodes(detailUrl, url);
    }
    
    res.json(playInfo);
  } catch (e) {
    console.error('获取播放地址失败:', e.message);
    res.json({ error: e.message, url: null, sources: [] });
  }
});

// 预解析当前剧集之后的播放地址
async function prefetchNextEpisodes(detailUrl, currentPlayUrl) {
  try {
    // 先从缓存获取详情
    const detailCacheKey = cache.generateKey('detail', detailUrl);
    const detail = await cache.get(detailCacheKey);
    
    if (!detail || !detail.episodes || detail.episodes.length === 0) {
      return;
    }
    
    // 找到当前播放的剧集索引
    const currentIndex = detail.episodes.findIndex(ep => ep.link === currentPlayUrl);
    if (currentIndex === -1) {
      return;
    }
    
    // 预解析后面 5 集
    const nextEpisodes = detail.episodes.slice(currentIndex + 1, currentIndex + 6);
    if (nextEpisodes.length === 0) {
      return;
    }
    
    console.log(`🔮 预解析后续 ${nextEpisodes.length} 集播放地址`);
    
    for (const ep of nextEpisodes) {
      if (ep.link) {
        prefetchPlayUrl(ep.link);
      }
    }
  } catch (e) {
    console.error('预解析后续剧集失败:', e.message);
  }
}

// 批量预解析接口（可选，供前端主动触发）
app.post('/api/prefetch', async (req, res) => {
  const { detailUrls, playUrls } = req.body;
  let queued = 0;
  
  if (detailUrls && Array.isArray(detailUrls)) {
    for (const url of detailUrls.slice(0, 20)) {
      prefetchDetail(url);
      queued++;
    }
  }
  
  if (playUrls && Array.isArray(playUrls)) {
    for (const url of playUrls.slice(0, 50)) {
      prefetchPlayUrl(url);
      queued++;
    }
  }
  
  res.json({ success: true, queued, message: `已加入预解析队列` });
});

// 清除缓存接口
app.post('/api/cache/clear', async (req, res) => {
  const { prefix } = req.body;
  try {
    if (prefix) {
      await cache.clearByPrefix(prefix);
      res.json({ success: true, message: `已清除 ${prefix} 缓存` });
    } else {
      await cache.clearByPrefix('home');
      await cache.clearByPrefix('category');
      await cache.clearByPrefix('search');
      await cache.clearByPrefix('detail');
      await cache.clearByPrefix('play');
      res.json({ success: true, message: '已清除所有缓存' });
    }
  } catch (e) {
    res.json({ success: false, error: e.message });
  }
});

// 缓存状态接口
app.get('/api/cache/stats', async (req, res) => {
  try {
    const stats = await cache.getStats();
    res.json({
      ...stats,
      prefetch: {
        active: activePrefetchCount,
        queued: prefetchQueue.length
      }
    });
  } catch (e) {
    res.json({ error: e.message });
  }
});

// 健康检查
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok',
    redis: cache.isConnected() ? 'connected' : 'disconnected',
    prefetch: {
      active: activePrefetchCount,
      queued: prefetchQueue.length
    }
  });
});

app.listen(PORT, () => {
  console.log(`🚀 Server running at http://localhost:${PORT}`);
  
  // 启动定时任务
  startScheduler();
});
