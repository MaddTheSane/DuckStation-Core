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
#import <OpenEmuBase/OpenEmuBase.h>
#define TickCount DuckTickCount
#include "core/types.h"
#include "core/system.h"
#include "core/host_display.h"
#include "core/host_interface.h"
#include "common/audio_stream.h"
#include "frontend-common/opengl_host_display.h"
#include "controller_interface.h"
Log_SetChannel(OpenEmuBridgeInterface);
#undef TickCount
#include <limits>
#include <optional>
#include <cstdint>
#include <vector>
#include <string>
#include <memory>

class OpenEmuAudioStream;
class OpenEmuOpenGLHostDisplay;
class OpenEmuControllerInterface;
class OpenEmuHostInterface;

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
		id<OEAudioBuffer> rb = [core audioBufferAtIndex:0];
		[rb write:m_output_buffer.data() maxLength:num_frames * sizeof(SampleType)];
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
	
	bool Render() override;
	
private:
	PlayStationGameCore *core;
};


class OpenEmuHostInterface : public HostInterface
{
public:
	OpenEmuHostInterface(PlayStationGameCore *gc);
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
	//void GetSystemAVInfo(struct retro_system_av_info* info, bool use_resolution_scale);
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
	PlayStationGameCore *core;
};

@interface PlayStationGameCore () <OEPSXSystemResponderClient>

@end

static __weak PlayStationGameCore *_current;


@implementation PlayStationGameCore {
	OpenEmuHostInterface *duckInterface;
}

- (instancetype)init
{
	if (self = [super init]) {
		duckInterface = new OpenEmuHostInterface(self);
		_current = self;
	}
	return self;
}



- (OEGameCoreRendering)gameCoreRendering
{
	//return OEGameCoreRenderingMetal1Video;
	return OEGameCoreRenderingOpenGL3Video;
}

- (oneway void)mouseMovedAtPoint:(OEIntPoint)point
{
	
}

- (oneway void)leftMouseDownAtPoint:(OEIntPoint)point
{
	
}

- (oneway void)leftMouseUp
{
	
}

- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point
{
	
}

- (oneway void)rightMouseUp
{
	
}

- (oneway void)didMovePSXJoystickDirection:(OEPSXButton)button withValue:(CGFloat)value forPlayer:(NSUInteger)player {
	
}


- (oneway void)didPushPSXButton:(OEPSXButton)button forPlayer:(NSUInteger)player {
	
}


- (oneway void)didReleasePSXButton:(OEPSXButton)button forPlayer:(NSUInteger)player {
	
}


- (void)fastForward:(BOOL)flag {
	
}

- (void)fastForwardAtSpeed:(CGFloat)fastForwardSpeed {
	
}

- (void)performBlock:(void (^)())block {
	
}

- (void)rewind:(BOOL)flag {
	
}

- (void)rewindAtSpeed:(CGFloat)rewindSpeed {
	
}

- (void)setFrameCallback:(void (^)(NSTimeInterval))block {
	
}

- (void)slowMotionAtSpeed:(CGFloat)slowMotionSpeed {
	
}

- (void)stepFrameBackward {
	
}

- (void)stepFrameForward {
	
}

- (NSUInteger)channelCount
{
	return 2;
}

- (NSUInteger)audioBitDepth
{
	return 16;
}

- (double)audioSampleRate
{
	return 44100;
}

@end

#pragma mark -

#define TickCount DuckTickCount
#include "common/assert.h"
#include "common/log.h"
#include "core/gpu.h"
#include "common/gl/program.h"
#include "common/gl/texture.h"
#undef TickCount
#include <array>
#include <tuple>

#pragma mark OpenEmuOpenGLHostDisplay methods -

bool OpenEmuOpenGLHostDisplay::CreateRenderDevice(const WindowInfo& wi, std::string_view adapter_name, bool debug_device)
{
	return false;
}

void OpenEmuOpenGLHostDisplay::DestroyRenderDevice()
{
	
}

void OpenEmuOpenGLHostDisplay::ResizeRenderWindow(s32 new_window_width, s32 new_window_height) {
	
}

void OpenEmuOpenGLHostDisplay::SetVSync(bool enabled)
{
	
}

bool OpenEmuOpenGLHostDisplay::Render() {
	return false;
}


#pragma mark -

#define TickCount DuckTickCount
#include "common/assert.h"
#include "common/byte_stream.h"
#include "common/file_system.h"
#include "common/log.h"
#include "common/string_util.h"
#include "core/analog_controller.h"
#include "core/bus.h"
#include "core/cheats.h"
#include "core/digital_controller.h"
#include "core/gpu.h"
#include "core/system.h"
#undef TickCount
#include <array>
#include <cstring>
#include <tuple>
#include <utility>
#include <vector>


#pragma mark OpenEmuHostInterface methods -

OpenEmuHostInterface::OpenEmuHostInterface(PlayStationGameCore *gc): core(gc) {}
OpenEmuHostInterface::~OpenEmuHostInterface() = default;

bool OpenEmuHostInterface::Initialize() {
	if (!HostInterface::Initialize())
	  return false;

	return true;
}

void OpenEmuHostInterface::InitInterfaces()
{
	
}

void OpenEmuHostInterface::Shutdown()
{
	
}

void OpenEmuHostInterface::ReportError(const char* message)
{
	
}

void OpenEmuHostInterface::ReportMessage(const char* message)
{
	
}

bool OpenEmuHostInterface::ConfirmMessage(const char* message)
{
	return true;
}

void OpenEmuHostInterface::AddOSDMessage(std::string message, float duration)
{
	
}

void OpenEmuHostInterface::GetGameInfo(const char* path, CDImage* image, std::string* code, std::string* title)
{
	if (image)
	  *code = System::GetGameCodeForImage(image);
}

std::string OpenEmuHostInterface::GetSharedMemoryCardPath(u32 slot) const
{
	return "";
}

std::string OpenEmuHostInterface::GetGameMemoryCardPath(const char* game_code, u32 slot) const
{
	return [core.batterySavesDirectoryPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%s-%d.mcd", game_code, slot]].fileSystemRepresentation;
}

std::string OpenEmuHostInterface::GetShaderCacheBasePath() const
{
	return [core.supportDirectoryPath stringByAppendingPathComponent:@"ShaderCache"].fileSystemRepresentation;
}

std::string OpenEmuHostInterface::GetStringSettingValue(const char* section, const char* key, const char* default_value)
{
	return "";
}

std::string OpenEmuHostInterface::GetBIOSDirectory()
{
	return core.biosDirectoryPath.fileSystemRepresentation;
}

bool OpenEmuHostInterface::AcquireHostDisplay()
{
	m_display = std::make_unique<OpenEmuOpenGLHostDisplay>(core);
	return true;
}

void OpenEmuHostInterface::ReleaseHostDisplay()
{
	if (m_hw_render_display) {
		m_hw_render_display->DestroyRenderDevice();
		m_hw_render_display.reset();
	}
	
	m_display->DestroyRenderDevice();
	m_display.reset();
}

std::unique_ptr<AudioStream> OpenEmuHostInterface::CreateAudioStream(AudioBackend backend)
{
	return std::make_unique<OpenEmuAudioStream>(core);
}

void OpenEmuHostInterface::OnSystemDestroyed()
{
  HostInterface::OnSystemDestroyed();
  m_using_hardware_renderer = false;
}

void OpenEmuHostInterface::CheckForSettingsChanges(const Settings& old_settings)
{
	
}
