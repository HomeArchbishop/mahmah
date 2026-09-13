# Web 人工测试台设计

日期：2026-09-08  
状态：已批准（方案 A）

## 目标

把现有「分析器」前端改成 **单人全链路** 后端人工测试 UI：保留牌桌视觉与布局模式，去掉分析；用鼠标完成 lobby → room → 出牌。

## 非目标

- 多席位同页模拟
- 推荐分 / 候选着 / observation 解码
- 服务端 bot 代打 / 定时器（未接线时 bot 座位会卡住，UI 仅提示等待）

## 界面

- 顶栏：连接状态、`player_id` / `room_id`、按钮（连 lobby、一键开桌、创建、加 bot、开始）
- 主区：复用 `BoardView` 牌桌；自家手牌可点
- 底栏：当前 `possible_actions` 大按钮 + 收发 JSON 日志

## 数据流

1. `ws://…/ws/lobby` → `welcome` → create / add_bot×3 / start_game  
2. `game_started` → 关 lobby → `ws://…/ws/room/{id}?player_id=`  
3. MJAI 事件还原 `BoardSnapshot`；`request_action` → 可点牌 / 动作按钮  
4. 上行 `dahai|none` + `request_id`（带 `actor`）

## Vite

代理 `/ws` → `localhost:8080`（WebSocket）。
