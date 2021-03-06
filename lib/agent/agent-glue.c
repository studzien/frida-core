#include "frida-agent.h"

#include "frida-interfaces.h"
#include "frida-payload.h"

#if defined (HAVE_ANDROID) && __ANDROID_API__ < __ANDROID_API_L__
# include <signal.h>
#endif
#ifdef HAVE_GLIB_SCHANNEL_STATIC
# include <glib-schannel-static.h>
#endif
#ifdef HAVE_GLIB_OPENSSL_STATIC
# include <glib-openssl-static.h>
#endif

void
_frida_agent_environment_init (void)
{
  gum_init_embedded ();
  frida_init_libc_shim ();

  g_thread_set_garbage_handler (_frida_agent_on_pending_thread_garbage, NULL);

#ifdef HAVE_GLIB_SCHANNEL_STATIC
  g_io_module_schannel_register ();
#endif
#ifdef HAVE_GLIB_OPENSSL_STATIC
  g_io_module_openssl_register ();
#endif

  gum_script_backend_get_type (); /* Warm up */
  frida_error_quark (); /* Initialize early so GDBus will pick it up */

#if defined (HAVE_ANDROID) && __ANDROID_API__ < __ANDROID_API_L__
  /*
   * We might be holding the dynamic linker's lock, so force-initialize
   * our bsd_signal() wrapper on this thread.
   */
  bsd_signal (G_MAXINT32, SIG_DFL);
#endif
}

void
_frida_agent_environment_deinit (void)
{
  frida_deinit_libc_shim ();
  gum_deinit_embedded ();
}
