extends ColorRect
## The .dim backdrop behind modal screens: radial rgba(10,20,50,.55) -> rgba(3,6,16,.88).

const SHADER := """
shader_type canvas_item;
void fragment() {
	float d = length((UV - vec2(0.5)) * vec2(1.4, 1.0));
	COLOR = mix(vec4(10.0, 20.0, 50.0, 0.55 * 255.0) / 255.0, vec4(3.0, 6.0, 16.0, 0.88 * 255.0) / 255.0, clamp(d * 1.25, 0.0, 1.0));
}
"""

func _ready() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	material = m
