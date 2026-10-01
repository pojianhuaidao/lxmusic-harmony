# 书源排查记录 · 喜马拉雅 toc 章节列表为空

## 结论速览

- 用户真机反馈喜马拉雅书源目录为空，最新包（a42853e / commit 49816b4）依旧。
- 根因不在引擎，而在**用户导入的喜马拉雅书源规则仍使用已失效的 fmobile 接口**。
- 引擎层（book_preload.js）经 Node 沙箱复测：模拟真机 LxHttp 桥请求头（GET 不带
  Content-Type，Accept: application/json，UA=Chrome69 WOW64）下，修正源后 3 个喜马拉雅
  源均正常返回章节列表。修复=改写源规则，用户重新导入即可。

## 根因分析

### 1. fmobile 接口已失效

喜马拉雅旧版移动接口：

```
http://mobile.ximalaya.com/fmobile-album/album/track/ts-1576706285548?ac=4G&albumId={id}&...
```

现在返回：

```json
{"msg":"亲，请求参数出错啦","ret":11}
```

（2026-10-01 实测，HTTP 200 但业务码 ret:11）

失效后，规则 `ruleToc.chapterList: $.data.list` 在 ret:11 响应中取不到任何节点，
toc 章节列表为空。常见 legado 喜马拉雅源（如「🎧喜马拉雅」「喜马拉雅」）的
bookUrl / tocUrl / nextTocUrl 全部写的是 fmobile 地址，因此**只要导入的源没改，
toc 永远为空**。

### 2. 引擎侧核查（排除项）

- `cleanMark`：只在最终 URL 输出处剥离 `,{...}` 尾串，不触碰 toc 列表本身；
- `not-audio` 校验仅作用于 content（音频直链校验），不作用于 toc；
- `doToc` 流程正确：fetchTextFor → specOf（仅加 sourceHeaders）→ requestBody 回放式取缓存，
  不向 GET 请求附加 Content-Type；
- 真机请求桥 `lxRequest`（core/source/LxHttp.ets）：GET 默认头
  `Accept: application/json` + `DEFAULT_UA`（Chrome69 WOW64），不主动加 Content-Type，
  与 Node 复测所用的请求头一致，不是触发 500 的因子。

> 注：Node 脚本若在 GET 上携带 `Content-Type: text/html,*/*;q=0.8` 会稳定触发喜马拉雅
> 反爬 500（ret:-1「系统繁忙」），这是**测试脚本自身**的头问题，真机 lxRequest 不携带，
> 复测脚本已改为模拟真机头。

## 修复内容

将失效的 fmobile 规则改写为喜马拉雅仍可用的老接口：

```
http://mobile.ximalaya.com/mobile/others/ca/album/track/{albumId}/true/1/200
```

对应规则变更：

| 字段 | 原值（失效） | 新值 |
| --- | --- | --- |
| ruleSearch.bookUrl / ruleExplore.bookUrl | fmobile-album ... albumId={$.albumInfo.id} / {$.id} | mobile/others/ca/album/track/{$.albumInfo.id}/true/1/200 等 |
| ruleBookInfo.tocUrl | fmobile-album ... albumId=@get:{book} | 删除（toc 直接用 bookUrl） |
| ruleToc.chapterList | $.data.list | $.tracks.list |
| ruleToc.chapterUrl | mpay pay 接口 / playPathAacv224 | playPathAacv224\|\|playPathAacv164\|\|playUrl64\|\|playUrl32 |
| ruleToc.nextTocUrl | fmobile-album 翻页 | 基于 tracks.maxPageId 的 @js 分页 |
| ruleContent.content | 依赖 seed 解密 / 空 | @js:baseUrl（章节地址即 m4a 直链） |

修正后的完整源清单见 `tools/ximalaya_sources_fixed.json`（含 3 个喜马拉雅源），
用户侧导入文件见会话产物 `audio_sources_fixed.json`。

## 复测证据（Node vm 沙箱，模拟真机 LxHttp 桥头）

| 源 | 链路 | toc 章节数 | 章节样例 URL |
| --- | --- | --- | --- |
| 🎧喜马拉雅 (idx7) | explore→bookInfo→toc | 61 | https://vod.xmcdn.com/download/1.0.0/storages/7e45-audiopay/F0/13/GKwRINsKVBsWAAsZ5QLojnrn.m4a?buy_key=... |
| 喜马拉雅 (idx8) | search(20)→bookInfo→toc→content×2 | 200 | http://aod.cos.tx.xmcdn.com/storages/d0a1-audiofreehighqps/01/40/GKwRIDoIz2SPAAGuPgJXBJkN.m4a（content 探测 audio/x-m4a, audio/mp4, HTTP 206） |
| 🎧喜马拉雅乃星 (idx13) | explore→bookInfo→toc→content×2 | 42 | https://vod.xmcdn.com/download/1.0.0/group4/M09/0B/A5/wKgO4V64pRKQmwc5ABRO_qABM8g779.m4a?buy_key=...（content 探测 audio/mp4, HTTP 206） |

## 待真机验证

- 用户重新导入修正后的喜马拉雅源（audio_sources_fixed.json / tools/ximalaya_sources_fixed.json），
  替换 App 内旧源后重测目录。
- 若用户实际使用的是 idx13（乃星）且仍失败，说明还存在其它真机侧差异（登录态 / Cookie /
  反爬），当前复测无法复现，需真机抓包补充。
