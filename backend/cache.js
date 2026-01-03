const Redis = require('ioredis');

// Redis 配置
const REDIS_CONFIG = {
  host: process.env.REDIS_HOST || '127.0.0.1',
  port: process.env.REDIS_PORT || 6379,
  password: process.env.REDIS_PASSWORD || undefined,
  db: process.env.REDIS_DB || 0,
  retryDelayOnFailover: 100,
  maxRetriesPerRequest: 3,
};

// 缓存过期时间（秒）
const TTL = {
  HOME: 60 * 30,           // 首页推荐 30 分钟
  CATEGORY: 60 * 15,       // 分类列表 15 分钟
  SEARCH: 60 * 60 * 24 * 7,    // 搜索结果 7 天
  DETAIL: 60 * 60 * 24 * 7,    // 剧集详情 7 天
  PLAY_URL: 60 * 60 * 24 * 7,  // 播放地址 7 天
};

let redis = null;
let isConnected = false;

// 初始化 Redis 连接
function initRedis() {
  try {
    redis = new Redis(REDIS_CONFIG);

    redis.on('connect', () => {
      console.log('✅ Redis 已连接');
      isConnected = true;
    });

    redis.on('error', (err) => {
      console.error('❌ Redis 错误:', err.message);
      isConnected = false;
    });

    redis.on('close', () => {
      console.log('⚠️ Redis 连接已关闭');
      isConnected = false;
    });

    return redis;
  } catch (err) {
    console.error('❌ Redis 初始化失败:', err.message);
    return null;
  }
}

// 生成缓存 key
function generateKey(prefix, params) {
  if (typeof params === 'string') {
    return `ccios:${prefix}:${params}`;
  }
  const paramStr = Object.entries(params)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}=${v}`)
    .join('&');
  return `ccios:${prefix}:${paramStr}`;
}

// 获取缓存
async function get(key) {
  if (!isConnected || !redis) return null;
  try {
    const data = await redis.get(key);
    if (data) {
      console.log(`📦 缓存命中: ${key}`);
      return JSON.parse(data);
    }
    return null;
  } catch (err) {
    console.error('缓存读取失败:', err.message);
    return null;
  }
}

// 设置缓存
async function set(key, value, ttl) {
  if (!isConnected || !redis) return false;
  try {
    await redis.setex(key, ttl, JSON.stringify(value));
    console.log(`💾 缓存写入: ${key} (TTL: ${ttl}s)`);
    return true;
  } catch (err) {
    console.error('缓存写入失败:', err.message);
    return false;
  }
}

// 删除缓存
async function del(key) {
  if (!isConnected || !redis) return false;
  try {
    await redis.del(key);
    return true;
  } catch (err) {
    console.error('缓存删除失败:', err.message);
    return false;
  }
}

// 清除指定前缀的缓存
async function clearByPrefix(prefix) {
  if (!isConnected || !redis) return false;
  try {
    const keys = await redis.keys(`ccios:${prefix}:*`);
    if (keys.length > 0) {
      await redis.del(...keys);
      console.log(`🗑️ 清除缓存: ${prefix} (${keys.length} 条)`);
    }
    return true;
  } catch (err) {
    console.error('缓存清除失败:', err.message);
    return false;
  }
}

// 带缓存的请求包装器
async function withCache(key, ttl, fetchFn) {
  // 尝试从缓存获取
  const cached = await get(key);
  if (cached !== null) {
    return cached;
  }

  // 执行请求
  const result = await fetchFn();

  // 写入缓存（只缓存有效数据）
  if (result && (Array.isArray(result) ? result.length > 0 : Object.keys(result).length > 0)) {
    await set(key, result, ttl);
  }

  return result;
}

// 获取缓存统计信息
async function getStats() {
  if (!isConnected || !redis) {
    return { connected: false, keys: 0, memory: '0' };
  }
  
  try {
    const info = await redis.info('memory');
    const memoryMatch = info.match(/used_memory_human:(\S+)/);
    const memory = memoryMatch ? memoryMatch[1] : '0';
    
    // 统计各类型缓存数量
    const prefixes = ['home', 'category', 'search', 'detail', 'play'];
    const counts = {};
    
    for (const prefix of prefixes) {
      const keys = await redis.keys(`ccios:${prefix}:*`);
      counts[prefix] = keys.length;
    }
    
    const totalKeys = Object.values(counts).reduce((a, b) => a + b, 0);
    
    return {
      connected: true,
      totalKeys,
      memory,
      counts
    };
  } catch (err) {
    console.error('获取缓存统计失败:', err.message);
    return { connected: true, error: err.message };
  }
}

module.exports = {
  initRedis,
  get,
  set,
  del,
  clearByPrefix,
  withCache,
  generateKey,
  getStats,
  TTL,
  isConnected: () => isConnected,
};
