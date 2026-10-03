# Changelog

## v0.8.8 (2026-10-03)

**DASH ClearKey 自动轮换**
- 频道新增私有 ClearKey URL 配置（与静态密钥同处，支持 ClearKey JSON / `kid:key` 文本）
- 仅在 init KID 变化时触发拉取；拉取失败进入"等密钥"状态，不计入连续失败，会话持续等待而非异常退出（30 分钟超时保护）

**面板国际化补完**
- EPG 查看页修复 admin 模式语言混乱（`applyI18n` 未执行）
- 频道编辑：DASH / PY 脚本 / 回看 / 工作模式英文翻译补齐；修复 `xnot` / `after not` 乱码
- 缓存后端显示跟随语言；ClearKey URL 帮助提示补上
- 新增 `i18n_check.py` 扫描脚本 + pre-commit hook，防翻译遗漏

**修复**
- 分组/频道删除按钮 `g is not defined`（模板 onclick 越界引用）
- 翻译设置保存报 `t is not a function`（局部变量遮蔽全局翻译函数）
- 录制对话框日期选择器跟随界面语言

**系统概览**
- CPU 卡：删除无意义的累计秒数，新增 Load Average（1/5/15 分钟）
