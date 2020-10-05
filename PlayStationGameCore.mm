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

class OpenEmuControllerInterface final : public ControllerInterface
{
public:
	OpenEmuControllerInterface();
	~OpenEmuControllerInterface();
	
	Backend GetBackend() const override;
	bool Initialize(CommonHostInterface* host_interface) override;
	void Shutdown() override;
	
	/// Returns the path of the optional game controller database file.
	std::string GetGameControllerDBFileName() const;
	
	// Removes all bindings. Call before setting new bindings.
	void ClearBindings() override;
	
	// Binding to events. If a binding for this axis/button already exists, returns false.
	bool BindControllerAxis(int controller_index, int axis_number, AxisCallback callback) override;
	bool BindControllerButton(int controller_index, int button_number, ButtonCallback callback) override;
	bool BindControllerAxisToButton(int controller_index, int axis_number, bool direction,
									ButtonCallback callback) override;
	bool BindControllerButtonToAxis(int controller_index, int button_number, AxisCallback callback) override;
	
	// Changing rumble strength.
	u32 GetControllerRumbleMotorCount(int controller_index) override;
	void SetControllerRumbleStrength(int controller_index, const float* strengths, u32 num_motors) override;
	
	// Set scaling that will be applied on axis-to-axis mappings
	bool SetControllerAxisScale(int controller_index, float scale = 1.00f) override;
	
	// Set deadzone that will be applied on axis-to-button mappings
	bool SetControllerDeadzone(int controller_index, float size = 0.25f) override;
	
	void PollEvents() override;
	
	//bool ProcessSDLEvent(const SDL_Event* event);
	
private:
	struct ControllerData
	{
		void* controller;
		void* haptic;
		int haptic_left_right_effect;
		int joystick_id;
		int player_id;
		
		// Scaling value of 1.30f to 1.40f recommended when using recent controllers
		float axis_scale = 1.00f;
		float deadzone = 0.25f;
		
		std::array<AxisCallback, MAX_NUM_AXISES> axis_mapping;
		std::array<ButtonCallback, MAX_NUM_BUTTONS> button_mapping;
		std::array<std::array<ButtonCallback, 2>, MAX_NUM_AXISES> axis_button_mapping;
		std::array<AxisCallback, MAX_NUM_BUTTONS> button_axis_mapping;
	};
	
	using ControllerDataVector = std::vector<ControllerData>;
	
	ControllerDataVector::iterator GetControllerDataForController(void* controller);
	ControllerDataVector::iterator GetControllerDataForJoystickId(int id);
	ControllerDataVector::iterator GetControllerDataForPlayerId(int id);
	int GetFreePlayerId() const;
	
	bool OpenGameController(int index);
	bool CloseGameController(int joystick_index, bool notify);
	//bool HandleControllerAxisEvent(const SDL_Event* event);
	//bool HandleControllerButtonEvent(const SDL_Event* event);
	
	ControllerDataVector m_controllers;
	
	std::mutex m_event_intercept_mutex;
	Hook::Callback m_event_intercept_callback;
	
	bool m_sdl_subsystem_initialized = false;
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
	return false;
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
	
}

std::string OpenEmuHostInterface::GetSharedMemoryCardPath(u32 slot) const
{
	return "";
}

std::string OpenEmuHostInterface::GetGameMemoryCardPath(const char* game_code, u32 slot) const
{
	return "";
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

#pragma mark -

#define TickCount DuckTickCount
#include "common/assert.h"
#include "common/file_system.h"
#include "common/log.h"
#include "core/controller.h"
#include "core/host_interface.h"
#include "core/system.h"
#undef TickCount

#pragma mark OpenEmuControllerInterface methods -

OpenEmuControllerInterface::OpenEmuControllerInterface() = default;

OpenEmuControllerInterface::~OpenEmuControllerInterface()
{
  Assert(m_controllers.empty());
}

ControllerInterface::Backend OpenEmuControllerInterface::GetBackend() const
{
	return ControllerInterface::Backend::None;
}

bool OpenEmuControllerInterface::Initialize(CommonHostInterface* host_interface)
{
	if (!ControllerInterface::Initialize(host_interface))
		return false;
	
#if 0
	FrontendCommon::EnsureSDLInitialized();
	
	const std::string gcdb_file_name = GetGameControllerDBFileName();
	if (FileSystem::FileExists(gcdb_file_name.c_str()))
	{
		Log_InfoPrintf("Loading game controller mappings from '%s'", gcdb_file_name.c_str());
		if (SDL_GameControllerAddMappingsFromFile(gcdb_file_name.c_str()) < 0)
		{
			Log_ErrorPrintf("SDL_GameControllerAddMappingsFromFile(%s) failed: %s", gcdb_file_name.c_str(), SDL_GetError());
		}
	}
	
	if (SDL_InitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER | SDL_INIT_HAPTIC) < 0)
	{
		Log_ErrorPrintf("SDL_InitSubSystem(SDL_INIT_JOYSTICK |SDL_INIT_GAMECONTROLLER | SDL_INIT_HAPTIC) failed");
		return false;
	}
	
	// we should open the controllers as the connected events come in, so no need to do any more here
	m_sdl_subsystem_initialized = true;
#endif
	return false;
}

void OpenEmuControllerInterface::Shutdown()
{
  while (!m_controllers.empty())
	CloseGameController(m_controllers.begin()->joystick_id, false);

  if (m_sdl_subsystem_initialized)
  {
	//SDL_QuitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER | SDL_INIT_HAPTIC);
	m_sdl_subsystem_initialized = false;
  }

  ControllerInterface::Shutdown();
}

std::string OpenEmuControllerInterface::GetGameControllerDBFileName() const
{
  return m_host_interface->GetUserDirectoryRelativePath("gamecontrollerdb.txt");
}

void OpenEmuControllerInterface::PollEvents()
{
//  for (;;)
//  {
//	SDL_Event ev;
//	if (SDL_PollEvent(&ev))
//	  ProcessSDLEvent(&ev);
//	else
//	  break;
//  }
}

//bool OpenEmuControllerInterface::ProcessSDLEvent(const SDL_Event* event)
//{
//  switch (event->type)
//  {
//	case SDL_CONTROLLERDEVICEADDED:
//	{
//	  Log_InfoPrintf("Controller %d inserted", event->cdevice.which);
//	  OpenGameController(event->cdevice.which);
//	  return true;
//	}
//
//	case SDL_CONTROLLERDEVICEREMOVED:
//	{
//	  Log_InfoPrintf("Controller %d removed", event->cdevice.which);
//	  CloseGameController(event->cdevice.which, true);
//	  return true;
//	}
//
//	case SDL_CONTROLLERAXISMOTION:
//	  return HandleControllerAxisEvent(event);
//
//	case SDL_CONTROLLERBUTTONDOWN:
//	case SDL_CONTROLLERBUTTONUP:
//	  return HandleControllerButtonEvent(event);
//
//	default:
//	  return false;
//  }
//}

OpenEmuControllerInterface::ControllerDataVector::iterator
OpenEmuControllerInterface::GetControllerDataForController(void* controller)
{
  return std::find_if(m_controllers.begin(), m_controllers.end(),
					  [controller](const ControllerData& cd) { return cd.controller == controller; });
}

OpenEmuControllerInterface::ControllerDataVector::iterator OpenEmuControllerInterface::GetControllerDataForJoystickId(int id)
{
  return std::find_if(m_controllers.begin(), m_controllers.end(),
					  [id](const ControllerData& cd) { return cd.joystick_id == id; });
}

OpenEmuControllerInterface::ControllerDataVector::iterator OpenEmuControllerInterface::GetControllerDataForPlayerId(int id)
{
  return std::find_if(m_controllers.begin(), m_controllers.end(),
					  [id](const ControllerData& cd) { return cd.player_id == id; });
}

int OpenEmuControllerInterface::GetFreePlayerId() const
{
  for (int player_id = 0;; player_id++)
  {
	size_t i;
	for (i = 0; i < m_controllers.size(); i++)
	{
	  if (m_controllers[i].player_id == player_id)
		break;
	}
	if (i == m_controllers.size())
	  return player_id;
  }

  return 0;
}

bool OpenEmuControllerInterface::OpenGameController(int index)
{
#if 0
  SDL_GameController* gcontroller = SDL_GameControllerOpen(index);
  SDL_Joystick* joystick = gcontroller ? SDL_GameControllerGetJoystick(gcontroller) : nullptr;
  if (!gcontroller || !joystick)
  {
	Log_WarningPrintf("Failed to open controller %d", index);
	if (gcontroller)
	  SDL_GameControllerClose(gcontroller);

	return false;
  }

  int joystick_id = SDL_JoystickInstanceID(joystick);
#if SDL_VERSION_ATLEAST(2, 0, 9)
  int player_id = SDL_GameControllerGetPlayerIndex(gcontroller);
#else
  int player_id = -1;
#endif
  if (player_id < 0 || GetControllerDataForPlayerId(player_id) != m_controllers.end())
  {
	const int free_player_id = GetFreePlayerId();
	Log_WarningPrintf(
	  "Controller %d (joystick %d) returned player ID %d, which is invalid or in use. Using ID %d instead.", index,
	  joystick_id, player_id, free_player_id);
	player_id = free_player_id;
  }

  Log_InfoPrintf("Opened controller %d (instance id %d, player id %d): %s", index, joystick_id, player_id,
				 SDL_GameControllerName(gcontroller));

  ControllerData cd = {};
  cd.controller = gcontroller;
  cd.player_id = player_id;
  cd.joystick_id = joystick_id;
  cd.haptic_left_right_effect = -1;

  SDL_Haptic* haptic = SDL_HapticOpenFromJoystick(joystick);
  if (haptic)
  {
	SDL_HapticEffect ef = {};
	ef.leftright.type = SDL_HAPTIC_LEFTRIGHT;
	ef.leftright.length = 1000;

	int ef_id = SDL_HapticNewEffect(haptic, &ef);
	if (ef_id >= 0)
	{
	  cd.haptic = haptic;
	  cd.haptic_left_right_effect = ef_id;
	}
	else
	{
	  Log_ErrorPrintf("Failed to create haptic left/right effect: %s", SDL_GetError());
	  if (SDL_HapticRumbleSupported(haptic) && SDL_HapticRumbleInit(haptic) != 0)
	  {
		cd.haptic = haptic;
	  }
	  else
	  {
		Log_ErrorPrintf("No haptic rumble supported: %s", SDL_GetError());
		SDL_HapticClose(haptic);
	  }
	}
  }

  if (cd.haptic)
	Log_InfoPrintf("Rumble is supported on '%s'", SDL_GameControllerName(gcontroller));
  else
	Log_WarningPrintf("Rumble is not supported on '%s'", SDL_GameControllerName(gcontroller));

  m_controllers.push_back(std::move(cd));
  OnControllerConnected(player_id);
  return true;
#else
	return false;
#endif
}

bool OpenEmuControllerInterface::CloseGameController(int joystick_index, bool notify)
{
//  auto it = GetControllerDataForJoystickId(joystick_index);
//  if (it == m_controllers.end())
//	return false;
//
//  const int player_id = it->player_id;
//
//  if (it->haptic)
//	SDL_HapticClose(static_cast<SDL_Haptic*>(it->haptic));
//
//  SDL_GameControllerClose(static_cast<SDL_GameController*>(it->controller));
//  m_controllers.erase(it);
//
//  if (notify)
//	OnControllerDisconnected(player_id);
//  return true;
	return false;
}

void OpenEmuControllerInterface::ClearBindings()
{
  for (auto& it : m_controllers)
  {
	for (AxisCallback& ac : it.axis_mapping)
	  ac = {};
	for (ButtonCallback& bc : it.button_mapping)
	  bc = {};
  }
}

bool OpenEmuControllerInterface::BindControllerAxis(int controller_index, int axis_number, AxisCallback callback)
{
  auto it = GetControllerDataForPlayerId(controller_index);
  if (it == m_controllers.end())
	return false;

  if (axis_number < 0 || axis_number >= MAX_NUM_AXISES)
	return false;

  it->axis_mapping[axis_number] = std::move(callback);
  return true;
}

bool OpenEmuControllerInterface::BindControllerButton(int controller_index, int button_number, ButtonCallback callback)
{
  auto it = GetControllerDataForPlayerId(controller_index);
  if (it == m_controllers.end())
	return false;

  if (button_number < 0 || button_number >= MAX_NUM_BUTTONS)
	return false;

  it->button_mapping[button_number] = std::move(callback);
  return true;
}

bool OpenEmuControllerInterface::BindControllerAxisToButton(int controller_index, int axis_number, bool direction,
														ButtonCallback callback)
{
  auto it = GetControllerDataForPlayerId(controller_index);
  if (it == m_controllers.end())
	return false;

  if (axis_number < 0 || axis_number >= MAX_NUM_AXISES)
	return false;

  it->axis_button_mapping[axis_number][BoolToUInt8(direction)] = std::move(callback);
  return true;
}

bool OpenEmuControllerInterface::BindControllerButtonToAxis(int controller_index, int button_number, AxisCallback callback)
{
  auto it = GetControllerDataForPlayerId(controller_index);
  if (it == m_controllers.end())
	return false;

  if (button_number < 0 || button_number >= MAX_NUM_BUTTONS)
	return false;

  it->button_axis_mapping[button_number] = std::move(callback);
  return true;
}

//bool OpenEmuControllerInterface::HandleControllerAxisEvent(const SDL_Event* ev)
//{
//  const float value = static_cast<float>(ev->caxis.value) / (ev->caxis.value < 0 ? 32768.0f : 32767.0f);
//  Log_DebugPrintf("controller %d axis %d %d %f", ev->caxis.which, ev->caxis.axis, ev->caxis.value, value);
//
//  auto it = GetControllerDataForJoystickId(ev->caxis.which);
//  if (it == m_controllers.end())
//	return false;
//
//  if (DoEventHook(Hook::Type::Axis, it->player_id, ev->caxis.axis, value))
//	return true;
//
//  const AxisCallback& cb = it->axis_mapping[ev->caxis.axis];
//  if (cb)
//  {
//	// Apply axis scaling only when controller axis is mapped to an axis
//	cb(std::clamp(it->axis_scale * value, -1.0f, 1.0f));
//	return true;
//  }
//
//  // set the other direction to false so large movements don't leave the opposite on
//  const bool outside_deadzone = (std::abs(value) >= it->deadzone);
//  const bool positive = (value >= 0.0f);
//  const ButtonCallback& other_button_cb = it->axis_button_mapping[ev->caxis.axis][BoolToUInt8(!positive)];
//  const ButtonCallback& button_cb = it->axis_button_mapping[ev->caxis.axis][BoolToUInt8(positive)];
//  if (button_cb)
//  {
//	button_cb(outside_deadzone);
//	if (other_button_cb)
//	  other_button_cb(false);
//	return true;
//  }
//  else if (other_button_cb)
//  {
//	other_button_cb(false);
//	return true;
//  }
//  else
//  {
//	return false;
//  }
//}

//bool OpenEmuControllerInterface::HandleControllerButtonEvent(const SDL_Event* ev)
//{
//  Log_DebugPrintf("controller %d button %d %s", ev->cbutton.which, ev->cbutton.button,
//				  ev->cbutton.state == SDL_PRESSED ? "pressed" : "released");
//
//  auto it = GetControllerDataForJoystickId(ev->cbutton.which);
//  if (it == m_controllers.end())
//	return false;
//
//  const bool pressed = (ev->cbutton.state == SDL_PRESSED);
//  if (DoEventHook(Hook::Type::Button, it->player_id, ev->cbutton.button, pressed ? 1.0f : 0.0f))
//	return true;
//
//  const ButtonCallback& cb = it->button_mapping[ev->cbutton.button];
//  if (cb)
//  {
//	cb(pressed);
//	return true;
//  }
//
//  // Assume a half-axis, i.e. in 0..1 range
//  const AxisCallback& axis_cb = it->button_axis_mapping[ev->cbutton.button];
//  if (axis_cb)
//  {
//	axis_cb(pressed ? 1.0f : 0.0f);
//  }
//
//  return false;
//}

u32 OpenEmuControllerInterface::GetControllerRumbleMotorCount(int controller_index)
{
  auto it = GetControllerDataForPlayerId(controller_index);
  if (it == m_controllers.end())
	return 0;

  return (it->haptic_left_right_effect >= 0) ? 2 : (it->haptic ? 1 : 0);
}

void OpenEmuControllerInterface::SetControllerRumbleStrength(int controller_index, const float* strengths, u32 num_motors)
{
//  auto it = GetControllerDataForPlayerId(controller_index);
//  if (it == m_controllers.end())
//	return;
//
//  // we'll update before this duration is elapsed
//  static constexpr u32 DURATION = 100000;
//
//  SDL_Haptic* haptic = static_cast<SDL_Haptic*>(it->haptic);
//  if (it->haptic_left_right_effect >= 0 && num_motors > 1)
//  {
//	if (strengths[0] > 0.0f || strengths[1] > 0.0f)
//	{
//	  SDL_HapticEffect ef;
//	  ef.type = SDL_HAPTIC_LEFTRIGHT;
//	  ef.leftright.large_magnitude = static_cast<u32>(strengths[0] * 65535.0f);
//	  ef.leftright.small_magnitude = static_cast<u32>(strengths[1] * 65535.0f);
//	  ef.leftright.length = DURATION;
//	  SDL_HapticUpdateEffect(haptic, it->haptic_left_right_effect, &ef);
//	  SDL_HapticRunEffect(haptic, it->haptic_left_right_effect, SDL_HAPTIC_INFINITY);
//	}
//	else
//	{
//	  SDL_HapticStopEffect(haptic, it->haptic_left_right_effect);
//	}
//  }
//  else
//  {
//	float max_strength = 0.0f;
//	for (u32 i = 0; i < num_motors; i++)
//	  max_strength = std::max(max_strength, strengths[i]);
//
//	if (max_strength > 0.0f)
//	  SDL_HapticRumblePlay(haptic, max_strength, DURATION);
//	else
//	  SDL_HapticRumbleStop(haptic);
//  }
}

bool OpenEmuControllerInterface::SetControllerAxisScale(int controller_index, float scale /* = 1.00f */)
{
  auto it = GetControllerDataForPlayerId(controller_index);
  if (it == m_controllers.end())
	return false;

  it->axis_scale = std::clamp(std::abs(scale), 0.01f, 1.50f);
  Log_InfoPrintf("Controller %d axis scale set to %f", controller_index, it->axis_scale);
  return true;
}

bool OpenEmuControllerInterface::SetControllerDeadzone(int controller_index, float size /* = 0.25f */)
{
  auto it = GetControllerDataForPlayerId(controller_index);
  if (it == m_controllers.end())
	return false;

  it->deadzone = std::clamp(std::abs(size), 0.01f, 0.99f);
  Log_InfoPrintf("Controller %d deadzone size set to %f", controller_index, it->deadzone);
  return true;
}
