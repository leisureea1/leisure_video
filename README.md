# Leisure 影视播放应用

极简、现代化的 iOS 影视播放应用，遵循 Apple HIG 设计规范。

## 项目结构

```
ccios_app/
├── backend/              # Node.js 后端服务
│   ├── server.js         # Express 服务入口
│   ├── scraper.js        # 数据抓取模块
│   ├── cache.js          # Redis 缓存模块
│   └── package.json
└── flutter/              # Flutter iOS 前端
    └── lib/
        ├── main.dart
        ├── models/
        ├── providers/
        ├── screens/
        ├── services/
        └── widgets/
```

## 功能特性

- 🎬 首页推荐 - 横向滚动卡片布局
- 📂 分类浏览 - 网格/列表切换
- � 分智能搜索 - 支持片名、演员搜索
- � 视能频播放 - 倍速、进度、全屏控制
- ❤️ 收藏追剧 - 本地持久化存储
- 📜 历史记录 - 自动保存播放进度
- 🌙 深色模式 - 跟随系统自动切换

## 后端性能优化

### 缓存策略

使用 Redis 实现多级缓存：

| 数据类型 | 缓存时间 |
|---------|---------|
| 首页推荐 | 30 分钟 |
| 分类列表 | 15 分钟 |
| 搜索结果 | 7 天 |
| 剧集详情 | 7 天 |
| 播放地址 | 7 天 |

### 异步预解析

- **搜索预解析**: 搜索结果返回后，自动异步解析所有结果的详情和播放地址
- **详情预解析**: 进入详情页后，自动异步解析所有剧集的播放地址
- **连续播放预解析**: 播放某集时，自动预解析后续 5 集的播放地址
- **并发控制**: 限制同时进行的预解析任务数为 3，避免请求过多

### 定时任务

服务器主动抓取，用户无需等待：

- 启动后 5 秒自动抓取首页 + 所有分类前 3 页
- 每 25 分钟自动刷新首页内容
- 每 12 分钟自动刷新分类内容

## API 接口

| 接口 | 方法 | 说明 |
|-----|------|-----|
| `/api/home` | GET | 首页推荐 |
| `/api/category` | GET | 分类列表 `?type=tv&page=1` |
| `/api/search` | GET | 搜索 `?keyword=关键词` |
| `/api/detail` | GET | 剧集详情 `?url=详情URL` |
| `/api/play` | GET | 播放地址 `?url=播放URL&detailUrl=详情URL` |
| `/api/prefetch` | POST | 批量预解析 `{detailUrls, playUrls}` |
| `/api/cache/clear` | POST | 清除缓存 `{prefix}` |
| `/api/cache/stats` | GET | 缓存统计 |
| `/health` | GET | 健康检查 |

## 运行方式

### 环境要求

- Node.js 18+
- Redis 6+

### 后端服务

```bash
cd backend
npm install
npm start
```

服务运行在 `http://localhost:8080`

### 环境变量（可选）

```bash
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0
```

### Flutter 应用

```bash
cd flutter
flutter pub get
flutter run
```

## 设计规范

- 遵循 iOS Human Interface Guidelines
- 使用 Cupertino 组件风格
- 支持 iPhone / iPad 自适应布局
- 支持横竖屏切换
- 流畅的手势交互和动画
