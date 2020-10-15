#include "PlayStationGameCore.h"
#include "context_agl.h"
#include "common/assert.h"
#include "common/log.h"
#include "glad.h"
#include <dlfcn.h>
Log_SetChannel(GL::ContextAGL);

namespace GL {
ContextAGL::ContextAGL(const WindowInfo& wi) : Context(wi)
{
  m_opengl_module_handle = dlopen("/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL", RTLD_NOW);
  if (!m_opengl_module_handle)
    Log_ErrorPrint("Could not open OpenGL.framework, function lookups will probably fail");
}

ContextAGL::~ContextAGL()
{

}

std::unique_ptr<Context> ContextAGL::Create(const WindowInfo& wi, const Version* versions_to_try,
                                            size_t num_versions_to_try)
{
std::unique_ptr<ContextAGL> context = std::make_unique<ContextAGL>(wi);
    return context;
}

bool ContextAGL::Initialize(const Version* versions_to_try, size_t num_versions_to_try)
{

    MakeCurrent();
    
  return true;
}

void* ContextAGL::GetProcAddress(const char* name)
{
  void* addr = m_opengl_module_handle ? dlsym(m_opengl_module_handle, name) : nullptr;
  if (addr)
    return addr;

  return dlsym(RTLD_NEXT, name);
}

bool ContextAGL::ChangeSurface(const WindowInfo& new_wi)
{

  return true;
}

void ContextAGL::ResizeSurface(u32 new_surface_width /*= 0*/, u32 new_surface_height /*= 0*/)
{
  UpdateDimensions();
}

bool ContextAGL::UpdateDimensions()
{
  return true;
}

bool ContextAGL::SwapBuffers()
{
    [_current.renderDelegate didRenderFrameOnAlternateThread];
    
  return true;
}

bool ContextAGL::MakeCurrent()
{
    [_current.renderDelegate willRenderFrameOnAlternateThread];
    
    // Set the background color of the context to black
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    SwapBuffers();

  return true;
}

bool ContextAGL::DoneCurrent()
{
    return true;
}

bool ContextAGL::SetSwapInterval(s32 interval)
{
  return true;
}

std::unique_ptr<Context> ContextAGL::CreateSharedContext(const WindowInfo& wi)
{
 std::unique_ptr<ContextAGL> context = std::make_unique<ContextAGL>(wi);

  return context;
}

bool ContextAGL::CreateContext(NSOpenGLContext* share_context, int profile, bool make_current)
{
  return true;
}

void ContextAGL::BindContextToView()
{
}
} // namespace GL
