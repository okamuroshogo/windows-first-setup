#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Win キー単独ではスタートメニューを出さない ---
;     （Win+E / Win+R / Win+D などの組み合わせショートカットはそのまま有効）
;     キーを「押した瞬間」にダミーキー(vkFF=未割当)を注入することで、
;     Win 単独押しを無効化してスタートメニューが開くのを防ぐ。
;     ※「離す時」だと間に合わずメニューが出てしまうため、押下時に注入する。
~LWin::Send "{Blind}{vkFF}"
~RWin::Send "{Blind}{vkFF}"

; --- Ctrl+Space でスタートメニューを開く ---
;     Ctrl+Esc は Win 単独押しと同じく「スタートを開く」Windows 標準ショートカット。
;     {LWin} を送る方式だと AHK が自動マスクして開かないため、Ctrl+Esc を使う。
^Space::Send "^{Esc}"
