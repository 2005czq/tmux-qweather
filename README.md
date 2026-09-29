# tmux-qweather

基于 [和风天气 (QWeather)](https://www.qweather.com/) 的轻量级交互式 [tmux](https://github.com/tmux/tmux) 天气插件。

## 环境要求

- `tmux` >= 3.2
- `curl`, `jq`
- Nerd Font 字体（用于天气图标显示）
- 和风天气 API Key（可在 [dev.qweather.com](https://dev.qweather.com/) 免费申请）

## 安装

在 `~/.tmux.conf` 中添加：

```tmux
set -g @plugin '2005czq/tmux-qweather'
set -g status-right '#{weather}'
```

在 tmux 内按 `prefix + I` 通过 TPM 完成安装。

## 配置

新建统一配置文件 `~/.config/tmux-qweather/config.json`：

```json
{
  "key": "你的和风天气API_KEY",
  "host": "devapi.qweather.com",
  "current": "北京",
  "locations": {
    "北京": "39.9042,116.4074",
    "上海": "31.2304,121.4737"
  }
}
```

- `key`：和风天气控制台获取的 API Key。
- `host`：请求域名（默认 `devapi.qweather.com`；若使用的是新控制台项目生成的 Key，请填入专属项目域名 `xxxx.re.qweatherapi.com`）。
- `current`：默认选中的地点名称。
- `locations`：多地点经纬度映射（格式为 `"地点名称": "纬度,经度"`）。

## 开源协议

[MIT](LICENSE)
