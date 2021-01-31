// Copyright (c) 2021, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import <Foundation/Foundation.h>
#import "PlayStationGameCore.h"

#define TickCount DuckTickCount
#include "OpenEmuOpenGLHostDisplay.hpp"
#include "common/align.h"
#include "common/assert.h"
#include "common/log.h"
#include "postprocessing_shadergen.h"
#include "context_agl.h"
#include <array>
#include <tuple>
Log_SetChannel(OpenEmuHostDisplay);
#undef TickCount

#include <os/log.h>

extern os_log_t OE_CORE_LOG;

class OEOGLHostDisplayTexture : public HostDisplayTexture
{
public:
	OEOGLHostDisplayTexture(GL::Texture texture, HostDisplayPixelFormat format)
	: m_texture(std::move(texture)), m_format(format){}
	~OEOGLHostDisplayTexture() override = default;
	
	void* GetHandle() const override { return reinterpret_cast<void*>(static_cast<uintptr_t>(m_texture.GetGLId())); }
	u32 GetWidth() const override { return m_texture.GetWidth(); }
	u32 GetHeight() const override { return m_texture.GetHeight(); }
	u32 GetLayers() const override { return 1; }
	u32 GetLevels() const override { return 1; }
	u32 GetSamples() const override { return m_texture.GetSamples(); }
	HostDisplayPixelFormat GetFormat() const override { return m_format; }
	
	GLuint GetGLID() const { return m_texture.GetGLId(); }
	
private:
	GL::Texture m_texture;
	HostDisplayPixelFormat m_format;
};

OpenEmuOpenGLHostDisplay::OpenEmuOpenGLHostDisplay(PlayStationGameCore *core) : _current(core)
{
	
}

OpenEmuOpenGLHostDisplay::~OpenEmuOpenGLHostDisplay()
{
	AssertMsg(!m_gl_context, "Context should have been destroyed by now");
}

HostDisplay::RenderAPI OpenEmuOpenGLHostDisplay::GetRenderAPI() const
{
	return RenderAPI::OpenGL;
}

void* OpenEmuOpenGLHostDisplay::GetRenderDevice() const
{
	return nullptr;
}

void* OpenEmuOpenGLHostDisplay::GetRenderContext() const
{
	return m_gl_context.get();
}

static constexpr std::array<std::tuple<GLenum, GLenum, GLenum>, static_cast<u32>(HostDisplayPixelFormat::Count)>
  s_display_pixel_format_mapping = {{
	{},                                                  // Unknown
	{GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE},               // RGBA8
	{GL_RGBA8, GL_BGRA, GL_UNSIGNED_BYTE},               // BGRA8
	{GL_RGB565, GL_RGB, GL_UNSIGNED_SHORT_5_6_5},        // RGB565
	{GL_RGB5_A1, GL_BGRA, GL_UNSIGNED_SHORT_1_5_5_5_REV} // RGBA5551
  }};

std::unique_ptr<HostDisplayTexture> OpenEmuOpenGLHostDisplay::CreateTexture(u32 width, u32 height, u32 layers, u32 levels,
																	 u32 samples, HostDisplayPixelFormat format,
																	 const void* data, u32 data_stride,
																	 bool dynamic /* = false */)
{
	if (layers != 1 || levels != 1)
		return {};
	
	const auto [gl_internal_format, gl_format, gl_type] = s_display_pixel_format_mapping[static_cast<u32>(format)];
	
	// TODO: Set pack width
	Assert(!data || data_stride == (width * sizeof(u32)));
	
	GL::Texture tex;
	if (!tex.Create(width, height, samples, gl_internal_format, gl_format, gl_type, data, data_stride))
		return {};
	
	return std::make_unique<OEOGLHostDisplayTexture>(std::move(tex), format);
}

void OpenEmuOpenGLHostDisplay::UpdateTexture(HostDisplayTexture* texture, u32 x, u32 y, u32 width, u32 height,
									  const void* texture_data, u32 texture_data_stride)
{
	OEOGLHostDisplayTexture* tex = static_cast<OEOGLHostDisplayTexture*>(texture);
	const auto [gl_internal_format, gl_format, gl_type] =
	s_display_pixel_format_mapping[static_cast<u32>(texture->GetFormat())];
	GLint alignment;
	if (texture_data_stride & 1)
		alignment = 1;
	else if (texture_data_stride & 2)
		alignment = 2;
	else
		alignment = 4;
	
	GLint old_texture_binding = 0, old_alignment = 0, old_row_length = 0;
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &old_texture_binding);
	glBindTexture(GL_TEXTURE_2D, tex->GetGLID());
	
	glGetIntegerv(GL_UNPACK_ALIGNMENT, &old_alignment);
	glPixelStorei(GL_UNPACK_ALIGNMENT, alignment);
	
	glGetIntegerv(GL_UNPACK_ROW_LENGTH, &old_row_length);
	glPixelStorei(GL_UNPACK_ROW_LENGTH, texture_data_stride / GetDisplayPixelFormatSize(texture->GetFormat()));
	
	glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, width, height, gl_format, gl_type, texture_data);
	
	glPixelStorei(GL_UNPACK_ROW_LENGTH, old_row_length);
	
	glPixelStorei(GL_UNPACK_ALIGNMENT, old_alignment);
	glBindTexture(GL_TEXTURE_2D, old_texture_binding);
}

bool OpenEmuOpenGLHostDisplay::DownloadTexture(const void* texture_handle, HostDisplayPixelFormat texture_format, u32 x, u32 y,
										u32 width, u32 height, void* out_data, u32 out_data_stride)
{
	GLint alignment;
	if (out_data_stride & 1)
		alignment = 1;
	else if (out_data_stride & 2)
		alignment = 2;
	else
		alignment = 4;
	
	GLint old_alignment = 0, old_row_length = 0;
	glGetIntegerv(GL_PACK_ALIGNMENT, &old_alignment);
	glPixelStorei(GL_PACK_ALIGNMENT, alignment);
	glGetIntegerv(GL_PACK_ROW_LENGTH, &old_row_length);
	glPixelStorei(GL_PACK_ROW_LENGTH, out_data_stride / GetDisplayPixelFormatSize(texture_format));
	
	const GLuint texture = static_cast<GLuint>(reinterpret_cast<uintptr_t>(texture_handle));
	const auto [gl_internal_format, gl_format, gl_type] =
	s_display_pixel_format_mapping[static_cast<u32>(texture_format)];
	
	GL::Texture::GetTextureSubImage(texture, 0, x, y, 0, width, height, 1, gl_format, gl_type, height * out_data_stride,
									out_data);
	
	glPixelStorei(GL_PACK_ALIGNMENT, old_alignment);
	glPixelStorei(GL_PACK_ROW_LENGTH, old_row_length);
	return true;
}

bool OpenEmuOpenGLHostDisplay::SupportsDisplayPixelFormat(HostDisplayPixelFormat format) const
{
	return (std::get<0>(s_display_pixel_format_mapping[static_cast<u32>(format)]) != static_cast<GLenum>(0));
}

bool OpenEmuOpenGLHostDisplay::BeginSetDisplayPixels(HostDisplayPixelFormat format, u32 width, u32 height, void** out_buffer,
													 u32* out_pitch)
{
	const u32 pixel_size = GetDisplayPixelFormatSize(format);
	const u32 stride = Common::AlignUpPow2(width * pixel_size, 4);
	const u32 size_required = stride * height * pixel_size;
	const u32 buffer_size = Common::AlignUpPow2(size_required * 2, 4 * 1024 * 1024);
	if (!m_display_pixels_texture_pbo || m_display_pixels_texture_pbo->GetSize() < buffer_size)
	{
		m_display_pixels_texture_pbo.reset();
		m_display_pixels_texture_pbo = GL::StreamBuffer::Create(GL_PIXEL_UNPACK_BUFFER, buffer_size);
		if (!m_display_pixels_texture_pbo)
			return false;
	}
	
	const auto map = m_display_pixels_texture_pbo->Map(GetDisplayPixelFormatSize(format), size_required);
	m_display_texture_format = format;
	m_display_pixels_texture_pbo_map_offset = map.buffer_offset;
	m_display_pixels_texture_pbo_map_size = size_required;
	*out_buffer = map.pointer;
	*out_pitch = stride;
	
	if (m_display_pixels_texture_id == 0)
	{
		glGenTextures(1, &m_display_pixels_texture_id);
		glBindTexture(GL_TEXTURE_2D, m_display_pixels_texture_id);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 1);
	}
	
	SetDisplayTexture(reinterpret_cast<void*>(static_cast<uintptr_t>(m_display_pixels_texture_id)), format, width, height,
					  0, 0, width, height);
	return true;
}

void OpenEmuOpenGLHostDisplay::EndSetDisplayPixels()
{
	const u32 width = static_cast<u32>(m_display_texture_view_width);
	const u32 height = static_cast<u32>(m_display_texture_view_height);
	
	const auto [gl_internal_format, gl_format, gl_type] =
	s_display_pixel_format_mapping[static_cast<u32>(m_display_texture_format)];
	
	// glTexImage2D should be quicker on Mali...
	m_display_pixels_texture_pbo->Unmap(m_display_pixels_texture_pbo_map_size);
	m_display_pixels_texture_pbo->Bind();
	glBindTexture(GL_TEXTURE_2D, m_display_pixels_texture_id);
	glTexImage2D(GL_TEXTURE_2D, 0, gl_internal_format, width, height, 0, gl_format, gl_type,
				 reinterpret_cast<void*>(static_cast<uintptr_t>(m_display_pixels_texture_pbo_map_offset)));
	glBindTexture(GL_TEXTURE_2D, 0);
	m_display_pixels_texture_pbo->Unbind();
	
	m_display_pixels_texture_pbo_map_offset = 0;
	m_display_pixels_texture_pbo_map_size = 0;
}

bool OpenEmuOpenGLHostDisplay::SetDisplayPixels(HostDisplayPixelFormat format, u32 width, u32 height, const void* buffer,
										 u32 pitch)
{
	if (m_display_pixels_texture_id == 0)
	{
		glGenTextures(1, &m_display_pixels_texture_id);
		glBindTexture(GL_TEXTURE_2D, m_display_pixels_texture_id);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 1);
	}
	else
	{
		glBindTexture(GL_TEXTURE_2D, m_display_pixels_texture_id);
	}
	
	const auto [gl_internal_format, gl_format, gl_type] = s_display_pixel_format_mapping[static_cast<u32>(format)];
	
	glTexImage2D(GL_TEXTURE_2D, 0, gl_internal_format, width, height, 0, gl_format, gl_type, buffer);
	
	glBindTexture(GL_TEXTURE_2D, 0);
	
	SetDisplayTexture(reinterpret_cast<void*>(static_cast<uintptr_t>(m_display_pixels_texture_id)), format, width, height,
					  0, 0, width, height);
	return true;
}

void OpenEmuOpenGLHostDisplay::SetVSync(bool enabled)
{
	if (m_gl_context->GetWindowInfo().type == WindowInfo::Type::Surfaceless)
		return;
	
	// Window framebuffer has to be bound to call SetSwapInterval.
	GLint current_fbo = 0;
	glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &current_fbo);
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
	m_gl_context->SetSwapInterval(enabled ? 1 : 0);
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, current_fbo);
	_current.renderDelegate.enableVSync = enabled;
}

const char* OpenEmuOpenGLHostDisplay::GetGLSLVersionString() const
{
	if (GLAD_GL_VERSION_3_3)
		return "#version 330";
	else
		return "#version 130";
}

std::string OpenEmuOpenGLHostDisplay::GetGLSLVersionHeader() const
{
	std::string header = GetGLSLVersionString();
	header += "\n\n";
	
	return header;
}

bool OpenEmuOpenGLHostDisplay::HasRenderDevice() const
{
  return static_cast<bool>(m_gl_context);
}

bool OpenEmuOpenGLHostDisplay::HasRenderSurface() const
{
	return m_window_info.type != WindowInfo::Type::Surfaceless;
}

bool OpenEmuOpenGLHostDisplay::CreateRenderDevice(const WindowInfo& wi, std::string_view adapter_name, bool debug_device,
												  bool threaded_presentation)
{
	static constexpr std::array<GL::Context::Version, 3> versArray {{{GL::Context::Profile::Core, 4, 1}, {GL::Context::Profile::Core, 3, 3}, {GL::Context::Profile::Core, 3, 2}}};
	
	m_gl_context = GL::ContextAGL::Create(wi, versArray.data(), versArray.size());
	if (!m_gl_context) {
		os_log_fault(OE_CORE_LOG, "Failed to create any GL context");
		return false;
	}
	
	gladLoadGL();
	m_window_info = wi;
	m_window_info.surface_width = m_gl_context->GetSurfaceWidth();
	m_window_info.surface_height = m_gl_context->GetSurfaceHeight();
	return true;
}

bool OpenEmuOpenGLHostDisplay::InitializeRenderDevice(std::string_view shader_cache_directory, bool debug_device,
													  bool threaded_presentation)
{
	glGetIntegerv(GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT, reinterpret_cast<GLint*>(&m_uniform_buffer_alignment));
	
	if (!CreateResources())
		return false;
	
	// Start with vsync on.
	SetVSync(true);
	
	return true;
}

bool OpenEmuOpenGLHostDisplay::MakeRenderContextCurrent()
{
	if (!m_gl_context->MakeCurrent())
	{
		Log_ErrorPrintf("Failed to make GL context current");
		return false;
	}
	
	return true;
}

bool OpenEmuOpenGLHostDisplay::DoneRenderContextCurrent()
{
	return m_gl_context->DoneCurrent();
}

void OpenEmuOpenGLHostDisplay::DestroyRenderDevice()
{
	if (!m_gl_context)
		return;
	
	DestroyResources();
	
	m_gl_context->DoneCurrent();
	m_gl_context.reset();
}

bool OpenEmuOpenGLHostDisplay::ChangeRenderWindow(const WindowInfo& new_wi)
{
	Assert(m_gl_context);
	
	if (!m_gl_context->ChangeSurface(new_wi))
	{
		Log_ErrorPrintf("Failed to change surface");
		return false;
	}
	
	m_window_info = new_wi;
	m_window_info.surface_width = m_gl_context->GetSurfaceWidth();
	m_window_info.surface_height = m_gl_context->GetSurfaceHeight();
	
	return true;
}

void OpenEmuOpenGLHostDisplay::ResizeRenderWindow(s32 new_window_width, s32 new_window_height)
{
	if (!m_gl_context)
		return;
	
	m_gl_context->ResizeSurface(static_cast<u32>(new_window_width), static_cast<u32>(new_window_height));
	m_window_info.surface_width = m_gl_context->GetSurfaceWidth();
	m_window_info.surface_height = m_gl_context->GetSurfaceHeight();
}

bool OpenEmuOpenGLHostDisplay::SupportsFullscreen() const
{
	return false;
}

bool OpenEmuOpenGLHostDisplay::IsFullscreen()
{
	return false;
}

bool OpenEmuOpenGLHostDisplay::SetFullscreen(bool fullscreen, u32 width, u32 height, float refresh_rate)
{
	return false;
}

void OpenEmuOpenGLHostDisplay::DestroyRenderSurface()
{
	if (!m_gl_context)
		return;
	
	m_window_info = {};
	if (!m_gl_context->ChangeSurface(m_window_info))
		Log_ErrorPrintf("Failed to switch to surfaceless");
}

bool OpenEmuOpenGLHostDisplay::CreateResources()
{
	static constexpr char fullscreen_quad_vertex_shader[] = R"(
uniform vec4 u_src_rect;
out vec2 v_tex0;

void main()
{
  vec2 pos = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  v_tex0 = u_src_rect.xy + pos * u_src_rect.zw;
  gl_Position = vec4(pos * vec2(2.0f, -2.0f) + vec2(-1.0f, 1.0f), 0.0f, 1.0f);
}
)";

	static constexpr char display_fragment_shader[] = R"(
uniform sampler2D samp0;

in vec2 v_tex0;
out vec4 o_col0;

void main()
{
  o_col0 = vec4(texture(samp0, v_tex0).rgb, 1.0);
}
)";

	static constexpr char cursor_fragment_shader[] = R"(
uniform sampler2D samp0;

in vec2 v_tex0;
out vec4 o_col0;

void main()
{
  o_col0 = texture(samp0, v_tex0);
}
)";

	if (!m_display_program.Compile(GetGLSLVersionHeader() + fullscreen_quad_vertex_shader, {},
								   GetGLSLVersionHeader() + display_fragment_shader) ||
		!m_cursor_program.Compile(GetGLSLVersionHeader() + fullscreen_quad_vertex_shader, {},
								  GetGLSLVersionHeader() + cursor_fragment_shader))
	{
		Log_ErrorPrintf("Failed to compile display shaders");
		return false;
	}
	
	m_display_program.BindFragData(0, "o_col0");
	m_cursor_program.BindFragData(0, "o_col0");
	
	if (!m_display_program.Link() || !m_cursor_program.Link())
	{
		Log_ErrorPrintf("Failed to link display programs");
		return false;
	}
	
	m_display_program.Bind();
	m_display_program.RegisterUniform("u_src_rect");
	m_display_program.RegisterUniform("samp0");
	m_display_program.Uniform1i(1, 0);
	m_cursor_program.Bind();
	m_cursor_program.RegisterUniform("u_src_rect");
	m_cursor_program.RegisterUniform("samp0");
	m_cursor_program.Uniform1i(1, 0);
	
	glGenVertexArrays(1, &m_display_vao);
	
	// samplers
	glGenSamplers(1, &m_display_nearest_sampler);
	glSamplerParameteri(m_display_nearest_sampler, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glSamplerParameteri(m_display_nearest_sampler, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glGenSamplers(1, &m_display_linear_sampler);
	glSamplerParameteri(m_display_linear_sampler, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glSamplerParameteri(m_display_linear_sampler, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	
	return true;
}

void OpenEmuOpenGLHostDisplay::DestroyResources()
{
	m_post_processing_chain.ClearStages();
	m_post_processing_input_texture.Destroy();
	m_post_processing_ubo.reset();
	m_post_processing_stages.clear();
	
	if (m_display_pixels_texture_id != 0)
	{
		glDeleteTextures(1, &m_display_pixels_texture_id);
		m_display_pixels_texture_id = 0;
	}
	
	if (m_display_vao != 0)
	{
		glDeleteVertexArrays(1, &m_display_vao);
		m_display_vao = 0;
	}
	if (m_display_linear_sampler != 0)
	{
		glDeleteSamplers(1, &m_display_linear_sampler);
		m_display_linear_sampler = 0;
	}
	if (m_display_nearest_sampler != 0)
	{
		glDeleteSamplers(1, &m_display_nearest_sampler);
		m_display_nearest_sampler = 0;
	}
	
	m_cursor_program.Destroy();
	m_display_program.Destroy();
}

bool OpenEmuOpenGLHostDisplay::Render()
{
	GLuint framebuffer = [[[_current renderDelegate] presentationFramebuffer] unsignedIntValue];

	glDisable(GL_SCISSOR_TEST);
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, framebuffer);
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);

	RenderDisplay();

	RenderSoftwareCursor();

	m_gl_context->SwapBuffers();

	return true;
}

void OpenEmuOpenGLHostDisplay::RenderDisplay()
{
	if (!HasDisplayTexture())
		return;
	
	const auto [left, top, width, height] = CalculateDrawRect(GetWindowWidth(), GetWindowHeight(), m_display_top_margin);
	
	if (!m_post_processing_chain.IsEmpty())
	{
		ApplyPostProcessingChain(0, left, GetWindowHeight() - top - height, width, height, m_display_texture_handle,
								 m_display_texture_width, m_display_texture_height, m_display_texture_view_x,
								 m_display_texture_view_y, m_display_texture_view_width, m_display_texture_view_height);
		return;
	}
	
	RenderDisplay(left, GetWindowHeight() - top - height, width, height, m_display_texture_handle,
				  m_display_texture_width, m_display_texture_height, m_display_texture_view_x, m_display_texture_view_y,
				  m_display_texture_view_width, m_display_texture_view_height, m_display_linear_filtering);
}

void OpenEmuOpenGLHostDisplay::RenderDisplay(s32 left, s32 bottom, s32 width, s32 height, void* texture_handle,
									  u32 texture_width, s32 texture_height, s32 texture_view_x, s32 texture_view_y,
									  s32 texture_view_width, s32 texture_view_height, bool linear_filter)
{
	glViewport(left, bottom, width, height);
	glDisable(GL_BLEND);
	glDisable(GL_CULL_FACE);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_SCISSOR_TEST);
	glDepthMask(GL_FALSE);
	glBindTexture(GL_TEXTURE_2D, static_cast<GLuint>(reinterpret_cast<uintptr_t>(texture_handle)));
	m_display_program.Bind();
	
	const float position_adjust = m_display_linear_filtering ? 0.5f : 0.0f;
	const float size_adjust = m_display_linear_filtering ? 1.0f : 0.0f;
	const float flip_adjust = (texture_view_height < 0) ? -1.0f : 1.0f;
	m_display_program.Uniform4f(
								0, (static_cast<float>(texture_view_x) + position_adjust) / static_cast<float>(texture_width),
								(static_cast<float>(texture_view_y) + (position_adjust * flip_adjust)) / static_cast<float>(texture_height),
								(static_cast<float>(texture_view_width) - size_adjust) / static_cast<float>(texture_width),
								(static_cast<float>(texture_view_height) - (size_adjust * flip_adjust)) / static_cast<float>(texture_height));
	glBindSampler(0, linear_filter ? m_display_linear_sampler : m_display_nearest_sampler);
	glBindVertexArray(m_display_vao);
	glDrawArrays(GL_TRIANGLES, 0, 3);
	glBindSampler(0, 0);
}

void OpenEmuOpenGLHostDisplay::RenderSoftwareCursor()
{
  if (!HasSoftwareCursor())
	return;

  const auto [left, top, width, height] = CalculateSoftwareCursorDrawRect();
  RenderSoftwareCursor(left, GetWindowHeight() - top - height, width, height, m_cursor_texture.get());
}

void OpenEmuOpenGLHostDisplay::RenderSoftwareCursor(s32 left, s32 bottom, s32 width, s32 height,
											 HostDisplayTexture* texture_handle)
{
	glViewport(left, bottom, width, height);
	glEnable(GL_BLEND);
	glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ZERO);
	glBlendEquationSeparate(GL_FUNC_ADD, GL_FUNC_ADD);
	glDisable(GL_CULL_FACE);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_SCISSOR_TEST);
	glDepthMask(GL_FALSE);
	m_cursor_program.Bind();
	glBindTexture(GL_TEXTURE_2D, static_cast<OEOGLHostDisplayTexture*>(texture_handle)->GetGLID());
	
	m_cursor_program.Uniform4f(0, 0.0f, 0.0f, 1.0f, 1.0f);
	glBindSampler(0, m_display_linear_sampler);
	glBindVertexArray(m_display_vao);
	glDrawArrays(GL_TRIANGLES, 0, 3);
	glBindSampler(0, 0);
}

bool OpenEmuOpenGLHostDisplay::SetPostProcessingChain(const std::string_view& config)
{
	if (config.empty())
	{
		m_post_processing_input_texture.Destroy();
		m_post_processing_stages.clear();
		m_post_processing_chain.ClearStages();
		return true;
	}
	
	if (!m_post_processing_chain.CreateFromString(config))
		return false;
	
	m_post_processing_stages.clear();
	
	FrontendCommon::PostProcessingShaderGen shadergen(HostDisplay::RenderAPI::OpenGL, false);
	
	for (u32 i = 0; i < m_post_processing_chain.GetStageCount(); i++)
	{
		const FrontendCommon::PostProcessingShader& shader = m_post_processing_chain.GetShaderStage(i);
		const std::string vs = shadergen.GeneratePostProcessingVertexShader(shader);
		const std::string ps = shadergen.GeneratePostProcessingFragmentShader(shader);
		
		PostProcessingStage stage;
		stage.uniforms_size = shader.GetUniformsSize();
		if (!stage.program.Compile(vs, {}, ps))
		{
			Log_InfoPrintf("Failed to compile post-processing program, disabling.");
			m_post_processing_stages.clear();
			m_post_processing_chain.ClearStages();
			return false;
		}
		
		if (!shadergen.UseGLSLBindingLayout())
		{
			stage.program.BindUniformBlock("UBOBlock", 1);
			stage.program.Bind();
			stage.program.Uniform1i("samp0", 0);
		}
		
		if (!stage.program.Link())
		{
			Log_InfoPrintf("Failed to link post-processing program, disabling.");
			m_post_processing_stages.clear();
			m_post_processing_chain.ClearStages();
			return false;
		}
		
		m_post_processing_stages.push_back(std::move(stage));
	}
	
	if (!m_post_processing_ubo)
	{
		m_post_processing_ubo = GL::StreamBuffer::Create(GL_UNIFORM_BUFFER, 1 * 1024 * 1024);
		if (!m_post_processing_ubo)
		{
			Log_InfoPrintf("Failed to allocate uniform buffer for postprocessing");
			m_post_processing_stages.clear();
			m_post_processing_chain.ClearStages();
			return false;
		}
		
		m_post_processing_ubo->Unbind();
	}
	
	return true;
}

bool OpenEmuOpenGLHostDisplay::CheckPostProcessingRenderTargets(u32 target_width, u32 target_height)
{
	DebugAssert(!m_post_processing_stages.empty());
	
	if (m_post_processing_input_texture.GetWidth() != target_width ||
		m_post_processing_input_texture.GetHeight() != target_height)
	{
		if (!m_post_processing_input_texture.Create(target_width, target_height, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE) ||
			!m_post_processing_input_texture.CreateFramebuffer())
		{
			return false;
		}
	}
	
	const u32 target_count = (static_cast<u32>(m_post_processing_stages.size()) - 1);
	for (u32 i = 0; i < target_count; i++)
	{
		PostProcessingStage& pps = m_post_processing_stages[i];
		if (pps.output_texture.GetWidth() != target_width || pps.output_texture.GetHeight() != target_height)
		{
			if (!pps.output_texture.Create(target_width, target_height, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE) ||
				!pps.output_texture.CreateFramebuffer())
			{
				return false;
			}
		}
	}
	
	return true;
}

void OpenEmuOpenGLHostDisplay::ApplyPostProcessingChain(GLuint final_target, s32 final_left, s32 final_top, s32 final_width,
														s32 final_height, void* texture_handle, u32 texture_width,
														s32 texture_height, s32 texture_view_x, s32 texture_view_y,
														s32 texture_view_width, s32 texture_view_height)
{
	if (!CheckPostProcessingRenderTargets(GetWindowWidth(), GetWindowHeight()))
	{
		RenderDisplay(final_left, GetWindowHeight() - final_top - final_height, final_width, final_height, texture_handle,
					  texture_width, texture_height, texture_view_x, texture_view_y, texture_view_width,
					  texture_view_height, m_display_linear_filtering);
		return;
	}
	
	// downsample/upsample - use same viewport for remainder
	m_post_processing_input_texture.BindFramebuffer(GL_DRAW_FRAMEBUFFER);
	glClear(GL_COLOR_BUFFER_BIT);
	RenderDisplay(final_left, GetWindowHeight() - final_top - final_height, final_width, final_height, texture_handle,
				  texture_width, texture_height, texture_view_x, texture_view_y, texture_view_width, texture_view_height,
				  m_display_linear_filtering);
	
	texture_handle = reinterpret_cast<void*>(static_cast<uintptr_t>(m_post_processing_input_texture.GetGLId()));
	texture_width = m_post_processing_input_texture.GetWidth();
	texture_height = m_post_processing_input_texture.GetHeight();
	texture_view_x = final_left;
	texture_view_y = final_top;
	texture_view_width = final_width;
	texture_view_height = final_height;
	
	m_post_processing_ubo->Bind();
	
	const u32 final_stage = static_cast<u32>(m_post_processing_stages.size()) - 1u;
	for (u32 i = 0; i < static_cast<u32>(m_post_processing_stages.size()); i++)
	{
		PostProcessingStage& pps = m_post_processing_stages[i];
		if (i == final_stage)
		{
			glBindFramebuffer(GL_DRAW_FRAMEBUFFER, final_target);
		}
		else
		{
			pps.output_texture.BindFramebuffer(GL_DRAW_FRAMEBUFFER);
			glClear(GL_COLOR_BUFFER_BIT);
		}
		
		pps.program.Bind();
		glBindSampler(0, m_display_linear_sampler);
		glBindTexture(GL_TEXTURE_2D, static_cast<GLuint>(reinterpret_cast<uintptr_t>(texture_handle)));
		glBindSampler(0, m_display_nearest_sampler);
		
		const auto map_result = m_post_processing_ubo->Map(m_uniform_buffer_alignment, pps.uniforms_size);
		m_post_processing_chain.GetShaderStage(i).FillUniformBuffer(
																	map_result.pointer, texture_width, texture_height, texture_view_x, texture_view_y, texture_view_width,
																	texture_view_height, GetWindowWidth(), GetWindowHeight(), 0.0f);
		m_post_processing_ubo->Unmap(pps.uniforms_size);
		glBindBufferRange(GL_UNIFORM_BUFFER, 1, m_post_processing_ubo->GetGLBufferId(), map_result.buffer_offset,
						  pps.uniforms_size);
		
		glDrawArrays(GL_TRIANGLES, 0, 3);
		
		if (i != final_stage)
			texture_handle = reinterpret_cast<void*>(static_cast<uintptr_t>(pps.output_texture.GetGLId()));
	}
	
	glBindSampler(0, 0);
	m_post_processing_ubo->Unbind();
}

