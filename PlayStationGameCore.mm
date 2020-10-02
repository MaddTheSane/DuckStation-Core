// Copyright (c) 2020, OpenEmu Team
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

#import "PlayStationGameCore.h"
#import "OEPSXSystemResponderClient.h"
#define TickCount DuckTickCount
#include "common/audio_stream.h"
#include "common/gl/program.h"
#include "common/gl/texture.h"
#include "core/host_display.h"
#include "frontend-common/opengl_host_display.h"
#include "core/host_interface.h"
#include "core/system.h"
#undef TickCount
#include <limits>
#include <optional>
#include <cstdint>
#include <vector>
#include <string>
#include <memory>

class OpenEmuAudioStream final : public AudioStream
{
public:
	OpenEmuAudioStream(PlayStationGameCore *gc): core(gc) {}
	~OpenEmuAudioStream() {};

protected:
	bool OpenDevice() override {
		m_output_buffer.resize(m_buffer_size * m_channels);
		return true;
	}
	void PauseDevice(bool paused) override {}
	void CloseDevice() override {}
	void FramesAvailable() override
	{
		const u32 num_frames = GetSamplesAvailable();
		ReadFrames(m_output_buffer.data(), num_frames, false);
		//g_retro_audio_sample_batch_callback(m_output_buffer.data(), num_frames);
	}

private:
	// TODO: Optimize this buffer away.
	std::vector<SampleType> m_output_buffer;
	PlayStationGameCore *core;
};

class OpenEmuOpenGLHostDisplay final : public FrontendCommon::OpenGLHostDisplay
{
public:
	OpenEmuOpenGLHostDisplay(PlayStationGameCore *gc): core(gc) {}
	~OpenEmuOpenGLHostDisplay() {};
	
	//static bool RequestHardwareRendererContext(retro_hw_render_callback* cb, bool prefer_gles);
	
	RenderAPI GetRenderAPI() const override {
		return RenderAPI::OpenGL;
	}
	
	bool CreateRenderDevice(const WindowInfo& wi, std::string_view adapter_name, bool debug_device) override;
	void DestroyRenderDevice() override;
	
	void ResizeRenderWindow(s32 new_window_width, s32 new_window_height) override;
	
	void SetVSync(bool enabled) override;
	
	bool Render() override {
		return false;
	}
	
private:
	PlayStationGameCore *core;
};

class OpenEmuHostInterface : public HostInterface
{
public:
	OpenEmuHostInterface();
	~OpenEmuHostInterface() override;
	
	void InitInterfaces();
	
	ALWAYS_INLINE u32 GetResolutionScale() const { return g_settings.gpu_resolution_scale; }
	
	bool Initialize() override;
	void Shutdown() override;
	
	void ReportError(const char* message) override;
	void ReportMessage(const char* message) override;
	bool ConfirmMessage(const char* message) override;
	void AddOSDMessage(std::string message, float duration = 2.0f) override;
	
	void GetGameInfo(const char* path, CDImage* image, std::string* code, std::string* title) override;
	std::string GetSharedMemoryCardPath(u32 slot) const override;
	std::string GetGameMemoryCardPath(const char* game_code, u32 slot) const override;
	std::string GetShaderCacheBasePath() const override;
	std::string GetStringSettingValue(const char* section, const char* key, const char* default_value = "") override;
	std::string GetBIOSDirectory() override;
	
	// Called by frontend
	void retro_get_system_av_info(struct retro_system_av_info* info);
	bool retro_load_game(const struct retro_game_info* game);
	void retro_run_frame();
	unsigned retro_get_region();
	size_t retro_serialize_size();
	bool retro_serialize(void* data, size_t size);
	bool retro_unserialize(const void* data, size_t size);
	void* retro_get_memory_data(unsigned id);
	size_t retro_get_memory_size(unsigned id);
	void retro_cheat_reset();
	void retro_cheat_set(unsigned index, bool enabled, const char* code);
	
protected:
	bool AcquireHostDisplay() override;
	void ReleaseHostDisplay() override;
	std::unique_ptr<AudioStream> CreateAudioStream(AudioBackend backend) override;
	void OnSystemDestroyed() override;
	void CheckForSettingsChanges(const Settings& old_settings) override;
	
private:
	bool SetCoreOptions();
	bool HasCoreVariablesChanged();
	void InitLogging();
	void InitDiskControlInterface();
	void InitRumbleInterface();
	
	void LoadSettings();
	void UpdateSettings();
	void UpdateControllers();
	void UpdateControllersDigitalController(u32 index);
	void UpdateControllersAnalogController(u32 index);
	void GetSystemAVInfo(struct retro_system_av_info* info, bool use_resolution_scale);
	void UpdateSystemAVInfo(bool use_resolution_scale);
	void UpdateGeometry();
	void UpdateLogging();
	
	// Hardware renderer setup.
	bool RequestHardwareRendererContext();
	void SwitchToHardwareRenderer();
	void SwitchToSoftwareRenderer();
	
	static void HardwareRendererContextReset();
	static void HardwareRendererContextDestroy();
	
	//retro_hw_render_callback m_hw_render_callback = {};
	std::unique_ptr<HostDisplay> m_hw_render_display;
	bool m_hw_render_callback_valid = false;
	bool m_using_hardware_renderer = false;
	std::optional<u32> m_next_disc_index;
	
	//retro_rumble_interface m_rumble_interface = {};
	bool m_rumble_interface_valid = false;
	bool m_supports_input_bitmasks = false;
	bool m_interfaces_initialized = false;
};

@interface PlayStationGameCore () <OEPSXSystemResponderClient>

@end

@implementation PlayStationGameCore

- (OEGameCoreRendering)gameCoreRendering
{
	return OEGameCoreRenderingOpenGL3Video;
}

@end
