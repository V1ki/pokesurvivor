class_name I18nExtra
extends RefCounted
## Translations of texts that only exist in the Godot port (or that the web dictionaries miss),
## loaded after data/lang_*.json. Same format as js/data/lang-*.js: key = the Spanish text as
## shown (runs of spaces count as one), {x} = gap. Patterns listed here are tried BEFORE the
## web ones (so a more specific pattern wins, e.g. "{x} shiny ..." before "{x} ...").
## Other agents keep writing Spanish strings: add their English / Chinese here when the web
## dictionaries don't have them.

const EN := {
	# ---- HUD / run ----
	# wild level line and boss bar (js/ui/hud.js): before "{x} Nv.{x}", which would also take them
	"POKÉMON SALVAJES NV. {x}": "WILD POKÉMON LV. {x}",
	"{x} · NV. {x}": "{x} · LV. {x}",
	"Nv. {x}": "Lv. {x}",
	"Nv.{x}": "Lv.{x}",
	"{x} Nv.{x}": "{x} Lv.{x}",
	"Nv.{x} > {x}": "Lv.{x} > {x}",
	"VEL ×{x}": "SPD ×{x}",
	"REG ×{x}": "REG ×{x}",
	"Elige una recompensa": "Choose a reward",
	"Elige una recompensa · 1 2 3": "Choose a reward · 1 2 3",
	"Cambiar opciones ({x}) · R": "Reroll ({x}) · R",
	"Cambiar opciones ({x})": "Reroll ({x})",
	"Sólo puedes llevar uno": "You can only hold one",
	"Sólo puedes llevar uno · 1 2": "You can only hold one · 1 2",
	"WASD moverse · 1–4 movimiento · Q/E ciclar · Esc pausa": "WASD move · 1–4 move slot · Q/E cycle · Esc pause",
	"Arrastra el dedo para moverte · toca un ataque para cambiarlo": "Drag your finger to move · tap a move to switch to it",
	"WASD moverse · 1-4 / Q / E o clic en un ataque para cambiarlo · Esc pausa": "WASD move · 1-4 / Q / E or click a move to switch · Esc pause",
	"¡{x} shiny te esperaba en la grieta!": "Shiny {x} was waiting in the rift!",
	"¡{x} shiny salvaje apareció!": "A wild shiny {x} appeared!",
	"{x} shiny es ahora tu compañero": "Shiny {x} is now your partner",
	# ---- personality traits (the web shows them in Spanish in English) ----
	"Valiente": "Brave", "Impulsivo": "Impulsive", "Prudente": "Careful", "Leal": "Loyal",
	"Paciente": "Patient", "Dulce": "Gentle", "Tímido": "Timid", "Travieso": "Naughty",
	"Sereno": "Calm", "Astuto": "Sly", "Alegre": "Cheerful", "Tenaz": "Tenacious",
	"Orgulloso": "Proud", "Solitario": "Lonely", "Tranquilo": "Relaxed", "Caótico": "Chaotic",
	# ---- menus ----
	"Sonido, gráficos, controles y partida": "Sound, graphics, controls and save",
	"Elegir de compañero": "Choose as partner",
	"Shinies conseguidos": "Shinies caught",
	"Shiny": "Shiny",
	"recogidas": "picked up",
	"{x} monedas": "{x} coins",
	"Volver a jugar": "Play again",
	"{x} · {x} niveles": "{x} · {x} levels",
	"{x} ticket ×10": "{x} ×10 ticket",
	"{x} tickets": "{x} tickets",
	"1 ticket": "1 ticket",
	"Tu perfil se guarda en esta partida (no hay perfil público sin conexión).": "Your profile is stored in this save (there is no public profile offline).",
	"Buscar por nombre": "Search by name",
	"¿Salir del juego?": "Quit the game?",
	"Salir del juego": "Quit game",
	# ---- settings ----
	"Se aplica al momento.": "Applies right away.",
	"Mando": "Gamepad",
	"stick izq. moverse · LB/RB cambiar · Start pausa · cruceta + A elegir · B atrás · Y cambiar opciones": "left stick move · LB/RB switch · Start pause · d-pad + A choose · B back · Y reroll",
	"elegir carta al subir de nivel, cambiar opciones": "choose a card when leveling up, reroll",
	"Partida de prueba en memoria (modo depuración): no se guarda nada.": "Test save in memory (debug mode): nothing is saved.",
	"Tu partida se guarda en este dispositivo ({x}).": "Your game is saved on this device ({x}).",
	"Importar del juego web": "Import from the web game",
	"En el juego web abre la consola del navegador (F12) y ejecuta copy(localStorage.getItem('ps.guest')) (con cuenta local: 'ps.save.<nombre>'). Pega aquí el texto copiado, o guárdalo como save_import.json en la carpeta de la partida. Sustituye tu partida actual (se guarda una copia de seguridad).":
		"In the web game open the browser console (F12) and run copy(localStorage.getItem('ps.guest')) (local account: 'ps.save.<name>'). Paste the copied text here, or save it as save_import.json in the save folder. It replaces your current save (a backup copy is kept).",
	"Pegar del portapapeles": "Paste from clipboard",
	"Importar": "Import",
	"Importar save_import.json": "Import save_import.json",
	"No existe {x}": "{x} does not exist",
	"Exportar": "Export",
	"Copia tu partida (JSON) al portapapeles y a save_export.json; se puede importar en el juego web con localStorage.setItem('ps.guest', …).":
		"Copies your save (JSON) to the clipboard and to save_export.json; the web game can import it with localStorage.setItem('ps.guest', …).",
	"Exportar partida (JSON)": "Export save (JSON)",
	"Copiada al portapapeles y guardada en {x}": "Copied to the clipboard and saved to {x}",
	"Borrar": "Delete",
	"No es un JSON de partida válido.": "That is not a valid save JSON.",
	"Se sustituirá tu partida actual por la importada (se guarda una copia de seguridad). ¿Seguro?": "Your current save will be replaced by the imported one (a backup copy is kept). Are you sure?",
	"Partida importada: {x} Pokémon, {x} monedas": "Save imported: {x} Pokémon, {x} coins",
	"El JSON no parece una partida de PokéSurvivor.": "That JSON doesn't look like a PokéSurvivor save.",
	"La partida es de una versión más nueva (v{x}).": "The save comes from a newer version (v{x}).",
	"Versión nativa para Android y PC (Godot)": "Native version for Android and PC (Godot)",
	"Juego de fans gratuito y sin ánimo de lucro: sin anuncios ni compras. Pokémon y sus personajes son propiedad de Nintendo, Creatures y GAME FREAK; este proyecto no está afiliado a ellos.":
		"A free, non-profit fan game: no ads, no purchases. Pokémon and its characters are property of Nintendo, Creatures and GAME FREAK; this project is not affiliated with them.",
	"· Sprites: PMD SpriteCollab y sus artistas (CC BY-NC 4.0).": "· Sprites: PMD SpriteCollab and its artists (CC BY-NC 4.0).",
	"· Datos de los Pokémon: PokéAPI.": "· Pokémon data: PokéAPI.",
	"· Música y sonidos: originales, generados por el propio juego.": "· Music and sounds: original, generated by the game itself.",
	"· Fuentes: Pixelify Sans y Fusion Pixel Font (OFL).": "· Fonts: Pixelify Sans and Fusion Pixel Font (OFL).",
	# ---- Settings › Acerca de: credits, licences, legal (parity audit) ----
	"Créditos completos": "Full credits",
	"Los sprites estilo Pokémon Mundo Misterioso vienen de SpriteCollab (github.com/PMDCollab/SpriteCollab), bajo licencia CC BY-NC 4.0 (creativecommons.org/licenses/by-nc/4.0): uso no comercial y con atribución a sus artistas.":
		"The Pokémon Mystery Dungeon-style sprites come from SpriteCollab (github.com/PMDCollab/SpriteCollab), under the CC BY-NC 4.0 license (creativecommons.org/licenses/by-nc/4.0): non-commercial use, with attribution to their artists.",
	"Artistas ({x})": "Artists ({x})",
	"Los sprites de cada artista (por número de Pokédex) están en CREDITS.md, incluido con el juego.": "Each artist's sprites (by Pokédex number) are listed in CREDITS.md, included with the game.",
	"Datos": "Data",
	"Stats base y nombres en español: PokeAPI (pokeapi.co).": "Base stats and Spanish names: PokeAPI (pokeapi.co).",
	"Fuentes": "Fonts",
	"Pixelify Sans (SIL Open Font License 1.1). El juego usa una versión modificada, «Pixelify PS», con los números redibujados para distinguirlos mejor.":
		"Pixelify Sans (SIL Open Font License 1.1). The game uses a modified version, “Pixelify PS”, with redrawn digits that are easier to tell apart.",
	"Para el chino: Fusion Pixel Font de TakWolf, 12 px proporcional, chino simplificado (SIL Open Font License 1.1), sin modificar.":
		"For Chinese: Fusion Pixel Font by TakWolf, 12 px proportional, Simplified Chinese (SIL Open Font License 1.1), unmodified.",
	"Licencia de Pixelify Sans": "Pixelify Sans license",
	"Licencia de Fusion Pixel Font": "Fusion Pixel Font license",
	"Marca": "Trademark",
	"Pokémon es propiedad de Nintendo, Creatures Inc. y GAME FREAK. Este es un proyecto de fan sin ánimo de lucro.": "Pokémon is property of Nintendo, Creatures Inc. and GAME FREAK. This is a non-profit fan project.",
	"PokéSurvivor es un juego hecho por fans, gratuito y sin ánimo de lucro. No tiene anuncios ni compras. Se puede apoyar con donaciones voluntarias, que se usan sólo para pagar los servidores y el dominio, y que no dan ninguna ventaja en el juego.":
		"PokéSurvivor is a game made by fans, free and non-profit. It has no ads or purchases. You can support it with voluntary donations, which are used only to pay for the servers and the domain and give no advantage in the game.",
	"Sprites de SpriteCollab (CC BY-NC 4.0, créditos completos en CREDITS.md del repositorio). Datos de la Pokédex de PokeAPI. Fuentes Pixelify Sans y Fusion Pixel Font (OFL). La música y los efectos de sonido son originales del proyecto.":
		"Sprites from SpriteCollab (CC BY-NC 4.0, full credits in the repository's CREDITS.md). Pokédex data from PokeAPI. Pixelify Sans and Fusion Pixel Font fonts (OFL). The music and sound effects are original to the project.",
	"Esta versión no tiene cuentas ni conexión: tu partida se guarda sólo en este dispositivo y no se envía a ningún sitio. No hay publicidad ni seguimiento.":
		"This version has no accounts and no connection: your save is kept only on this device and is never sent anywhere. There are no ads and no tracking.",
	"Ocupa toda la pantalla, sin el marco de la ventana.": "Fills the whole screen, without the window frame.",
	"Salir": "Exit",            # the fullscreen button (the web dictionary has the logout "Log out")
	"Tienes": "You have",       # gacha tickets line: "Tienes [ticket] N tickets y [ticket10] N tickets ×10"
	"tickets y": "tickets and",
}

const ZH := {
	# ---- HUD / run ----
	"POKÉMON SALVAJES NV. {x}": "野生宝可梦 {x} 级",
	"{x} · NV. {x}": "{x} · 等级 {x}",
	"Nv. {x}": "Lv. {x}",
	"Nv.{x}": "Lv.{x}",
	"{x} Nv.{x}": "{x} Lv.{x}",
	"Nv.{x} > {x}": "Lv.{x} > {x}",
	"ATK ×{x}": "攻击 ×{x}",
	"VEL ×{x}": "速度 ×{x}",
	"DEF ×{x}": "防御 ×{x}",
	"REG ×{x}": "回复 ×{x}",
	"Elige una recompensa": "选择奖励",
	"Elige una recompensa · 1 2 3": "选择奖励 · 1 2 3",
	"Cambiar opciones ({x}) · R": "刷新 ({x}) · R",
	"Cambiar opciones ({x})": "刷新 ({x})",
	"Sólo puedes llevar uno": "只能携带一个",
	"Sólo puedes llevar uno · 1 2": "只能携带一个 · 1 2",
	"WASD moverse · 1–4 movimiento · Q/E ciclar · Esc pausa": "WASD 移动 · 1–4 招式 · Q/E 切换 · Esc 暂停",
	"Arrastra el dedo para moverte · toca un ataque para cambiarlo": "拖动手指移动 · 点击招式进行切换",
	"¡{x} shiny te esperaba en la grieta!": "闪光{x}正在裂隙中等着你！",
	"¡{x} shiny salvaje apareció!": "野生的闪光{x}出现了！",
	"{x} shiny es ahora tu compañero": "闪光{x}现在是你的伙伴了",
	# ---- regions (the web keeps the Latin names) ----
	"Kanto": "关都",
	"Johto": "城都",
	"Hoenn": "丰缘",
	"Sinnoh": "神奥",
	"Kalos": "卡洛斯",
	"Alola": "阿罗拉",
	"Galar": "伽勒尔",
	"Paldea": "帕底亚",
	# ---- menus ----
	"Sonido, gráficos, controles y partida": "声音、画面、操作与存档",
	"Elegir de compañero": "设为伙伴",
	"Shinies conseguidos": "获得的闪光宝可梦",
	"Shiny": "闪光",
	"recogidas": "拾取",
	"{x} monedas": "{x} 宝可梦币",
	"Volver a jugar": "再玩一次",
	"{x} · {x} niveles": "{x} · {x} 级",
	"{x} ticket ×10": "{x} 张 ×10 扭蛋券",
	"{x} tickets": "{x} 张扭蛋券",
	"1 ticket": "1 张扭蛋券",
	"Tu perfil se guarda en esta partida (no hay perfil público sin conexión).": "你的个人资料保存在这份存档中（离线版没有公开资料）。",
	"Buscar por nombre": "按名字搜索",
	"¿Salir del juego?": "要退出游戏吗？",
	"Salir del juego": "退出游戏",
	# ---- settings ----
	"Se aplica al momento.": "立即生效。",
	"Mando": "手柄",
	"stick izq. moverse · LB/RB cambiar · Start pausa · cruceta + A elegir · B atrás · Y cambiar opciones": "左摇杆 移动 · LB/RB 切换 · Start 暂停 · 十字键 + A 选择 · B 返回 · Y 刷新",
	"elegir carta al subir de nivel, cambiar opciones": "升级时选择卡牌，刷新选项",
	"Partida de prueba en memoria (modo depuración): no se guarda nada.": "内存中的测试存档（调试模式）：不会保存任何内容。",
	"Tu partida se guarda en este dispositivo ({x}).": "你的存档保存在这台设备上（{x}）。",
	"Importar del juego web": "从网页版导入",
	"En el juego web abre la consola del navegador (F12) y ejecuta copy(localStorage.getItem('ps.guest')) (con cuenta local: 'ps.save.<nombre>'). Pega aquí el texto copiado, o guárdalo como save_import.json en la carpeta de la partida. Sustituye tu partida actual (se guarda una copia de seguridad).":
		"在网页版中打开浏览器控制台（F12），运行 copy(localStorage.getItem('ps.guest'))（本地账号：'ps.save.<名字>'）。把复制的文本粘贴到这里，或另存为存档文件夹里的 save_import.json。导入会替换当前存档（会保留一份备份）。",
	"Pegar del portapapeles": "从剪贴板粘贴",
	"Importar": "导入",
	"Importar save_import.json": "导入 save_import.json",
	"No existe {x}": "{x} 不存在",
	"Exportar": "导出",
	"Copia tu partida (JSON) al portapapeles y a save_export.json; se puede importar en el juego web con localStorage.setItem('ps.guest', …).":
		"把你的存档（JSON）复制到剪贴板并写入 save_export.json；网页版可用 localStorage.setItem('ps.guest', …) 导入。",
	"Exportar partida (JSON)": "导出存档（JSON）",
	"Copiada al portapapeles y guardada en {x}": "已复制到剪贴板并保存到 {x}",
	"Borrar": "删除",
	"No es un JSON de partida válido.": "这不是有效的存档 JSON。",
	"Se sustituirá tu partida actual por la importada (se guarda una copia de seguridad). ¿Seguro?": "当前存档将被导入的存档替换（会保留一份备份）。确定吗？",
	"Partida importada: {x} Pokémon, {x} monedas": "存档已导入：{x} 只宝可梦，{x} 宝可梦币",
	"El JSON no parece una partida de PokéSurvivor.": "这个 JSON 看起来不是 PokéSurvivor 的存档。",
	"La partida es de una versión más nueva (v{x}).": "该存档来自更新的版本（v{x}）。",
	"Versión nativa para Android y PC (Godot)": "安卓与电脑原生版（Godot）",
	"Juego de fans gratuito y sin ánimo de lucro: sin anuncios ni compras. Pokémon y sus personajes son propiedad de Nintendo, Creatures y GAME FREAK; este proyecto no está afiliado a ellos.":
		"免费、非营利的粉丝游戏：没有广告，也没有内购。宝可梦及其角色归 Nintendo、Creatures 与 GAME FREAK 所有；本项目与它们无关。",
	"· Sprites: PMD SpriteCollab y sus artistas (CC BY-NC 4.0).": "· 像素图：PMD SpriteCollab 及其画师（CC BY-NC 4.0）。",
	"· Datos de los Pokémon: PokéAPI.": "· 宝可梦数据：PokéAPI。",
	"· Música y sonidos: originales, generados por el propio juego.": "· 音乐和音效：原创，由游戏自身生成。",
	"· Fuentes: Pixelify Sans y Fusion Pixel Font (OFL).": "· 字体：Pixelify Sans 与 Fusion Pixel Font（均为 OFL）。",
	# ---- Settings › Acerca de: credits, licences, legal (parity audit) ----
	"Créditos completos": "完整致谢",
	"Sprites": "像素图",
	"Los sprites estilo Pokémon Mundo Misterioso vienen de SpriteCollab (github.com/PMDCollab/SpriteCollab), bajo licencia CC BY-NC 4.0 (creativecommons.org/licenses/by-nc/4.0): uso no comercial y con atribución a sus artistas.":
		"宝可梦不可思议的迷宫风格的像素图来自 SpriteCollab（github.com/PMDCollab/SpriteCollab），采用 CC BY-NC 4.0 许可（creativecommons.org/licenses/by-nc/4.0）：仅限非商业用途，并须署名其画师。",
	"Artistas ({x})": "画师（{x}）",
	"Los sprites de cada artista (por número de Pokédex) están en CREDITS.md, incluido con el juego.": "每位画师绘制的像素图（按图鉴编号）列在游戏附带的 CREDITS.md 中。",
	"Datos": "数据",
	"Stats base y nombres en español: PokeAPI (pokeapi.co).": "基础能力值与西班牙语名称：PokeAPI（pokeapi.co）。",
	"Fuentes": "字体",
	"Pixelify Sans (SIL Open Font License 1.1). El juego usa una versión modificada, «Pixelify PS», con los números redibujados para distinguirlos mejor.":
		"Pixelify Sans（SIL Open Font License 1.1）。游戏使用的是修改版“Pixelify PS”，重绘了数字，更容易区分。",
	"Para el chino: Fusion Pixel Font de TakWolf, 12 px proporcional, chino simplificado (SIL Open Font License 1.1), sin modificar.":
		"中文：TakWolf 的缝合像素字体 Fusion Pixel Font，12 px 比例字宽，简体中文（SIL Open Font License 1.1），未经修改。",
	"Licencia de Pixelify Sans": "Pixelify Sans 许可证",
	"Licencia de Fusion Pixel Font": "Fusion Pixel Font 许可证",
	"Marca": "商标",
	"Pokémon es propiedad de Nintendo, Creatures Inc. y GAME FREAK. Este es un proyecto de fan sin ánimo de lucro.": "宝可梦归任天堂、Creatures Inc. 和 GAME FREAK 所有。本作是非营利的粉丝项目。",
	"PokéSurvivor es un juego hecho por fans, gratuito y sin ánimo de lucro. No tiene anuncios ni compras. Se puede apoyar con donaciones voluntarias, que se usan sólo para pagar los servidores y el dominio, y que no dan ninguna ventaja en el juego.":
		"PokéSurvivor 是一款由粉丝制作的游戏，免费且非营利。没有广告，也没有内购。你可以通过自愿捐助来支持本作，捐款仅用于支付服务器和域名费用，不会带来任何游戏内优势。",
	"Sprites de SpriteCollab (CC BY-NC 4.0, créditos completos en CREDITS.md del repositorio). Datos de la Pokédex de PokeAPI. Fuentes Pixelify Sans y Fusion Pixel Font (OFL). La música y los efectos de sonido son originales del proyecto.":
		"像素图来自 SpriteCollab（CC BY-NC 4.0，完整致谢名单见代码仓库中的 CREDITS.md）。宝可梦图鉴数据来自 PokeAPI。字体：Pixelify Sans 与缝合像素字体 Fusion Pixel Font（均为 OFL）。音乐和音效均为本项目原创。",
	"Esta versión no tiene cuentas ni conexión: tu partida se guarda sólo en este dispositivo y no se envía a ningún sitio. No hay publicidad ni seguimiento.":
		"此版本没有账号，也不联网：你的存档只保存在本设备上，不会发送到任何地方。没有广告，也没有追踪。",
	"Ocupa toda la pantalla, sin el marco de la ventana.": "占满整个屏幕，不显示窗口边框。",
	"Tienes": "拥有",
	"tickets y": "张扭蛋券和",
}
