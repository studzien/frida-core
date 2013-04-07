#if DARWIN
using Gee;

namespace Frida {
	public class Fruitjector : Object {
		public signal void uninjected (uint id);

		private ResourceStore resource_store;
		private HelperFactory helper_factory = new HelperFactory ();
		private Gee.HashMap<uint, uint> pid_by_id = new Gee.HashMap<uint, uint> ();

		public async void close () {
			yield helper_factory.close ();

			resource_store = null;
		}

		public async uint inject (uint pid, AgentDescriptor desc, string data_string) throws IOError {
			if (resource_store == null) {
				resource_store = new ResourceStore ();
				helper_factory.resource_store = resource_store;
			}

			var filename = resource_store.ensure_copy_of (desc);
			var helper = yield helper_factory.obtain ();
			var id = yield helper.inject (pid, filename, data_string);
			pid_by_id[id] = pid;

			return id;
		}

		public bool any_still_injected () {
			return !pid_by_id.is_empty;
		}

		public bool is_still_injected (uint id) {
			return pid_by_id.has_key (id);
		}

		private class HelperInstance {
			private DBusConnection connection;
			private FruitjectorHelper proxy;

			public HelperInstance (DBusConnection connection, FruitjectorHelper proxy) {
				this.connection = connection;
				this.proxy = proxy;
			}

			public async void close () {
				try {
					yield proxy.stop ();
				} catch (IOError proxy_error) {
				}

				try {
					yield connection.close ();
				} catch (Error connection_error) {
				}
			}

			public async uint inject (uint pid, string filename, string data_string) throws IOError {
				return yield proxy.inject (pid, filename, data_string);
			}
		}

		private class HelperFactory {
			private MainContext main_context;
			private DBusServer server;
			private HelperInstance helper;
			private ArrayList<ObtainRequest> obtain_requests = new ArrayList<ObtainRequest> ();

			public ResourceStore resource_store {
				get;
				set;
			}

			public HelperFactory () {
				this.main_context = MainContext.get_thread_default ();
			}

			public async void close () {
				if (helper != null) {
					yield helper.close ();
					helper = null;
				}

				if (server != null) {
					server.stop ();
					server = null;
				}

				resource_store = null;
			}

			public async HelperInstance obtain () throws IOError {
				if (helper != null)
					return helper;

				if (obtain_requests.size == 0) {
					var source = new IdleSource ();
					source.set_callback (() => {
						do_obtain ();
						return false;
					});
					source.attach (main_context);
				}

				var request = new ObtainRequest (() => obtain.callback ());
				obtain_requests.add (request);
				yield;

				return request.get_result ();
			}

			private async void do_obtain () {
				DBusConnection connection = null;
				HelperInstance instance = null;
				TimeoutSource timeout_source = null;
				IOError error = null;

				try {
					if (server == null) {
						server = new DBusServer.sync ("unix:tmpdir=" + resource_store.tempdir.path, DBusServerFlags.AUTHENTICATION_ALLOW_ANONYMOUS, DBus.generate_guid ());
						server.start ();
					}
					var connection_handler = server.new_connection.connect ((c) => {
						connection = c;
						do_obtain.callback ();
						return true;
					});
					timeout_source = new TimeoutSource.seconds (2);
					timeout_source.set_callback (() => {
						error = new IOError.TIMED_OUT ("timed out");
						do_obtain.callback ();
						return false;
					});
					string[] argv = { server.address };
					spawn (resource_store.helper.path, argv);
					yield;
					server.disconnect (connection_handler);

					FruitjectorHelper proxy;
					if (error == null) {
						proxy = yield connection.get_proxy (null, FruitjectorObjectPath.HELPER);
						instance = new HelperInstance (connection, proxy);
					}
					timeout_source.destroy ();
				} catch (Error e) {
					if (timeout_source != null)
						timeout_source.destroy ();
					error = new IOError.FAILED (e.message);
				}

				complete_obtain (instance, error);
			}

			private async void complete_obtain (HelperInstance? instance, IOError? error) {
				this.helper = instance;

				foreach (var request in obtain_requests)
					request.complete (instance, error);
				obtain_requests.clear ();
			}

			private class ObtainRequest {
				public delegate void CompletionHandler ();
				private CompletionHandler handler;

				private HelperInstance helper;
				private IOError error;

				public ObtainRequest (owned CompletionHandler handler) {
					this.handler = (owned) handler;
				}

				public void complete (HelperInstance? helper, IOError? error) {
					this.helper = helper;
					this.error = error;
					handler ();
				}

				public HelperInstance get_result () throws IOError {
					if (helper == null)
						throw error;
					return helper;
				}
			}

			private static extern uint spawn (string path, string[] argv) throws IOError;
		}

		private class ResourceStore {
			public TemporaryDirectory tempdir {
				get;
				private set;
			}

			public TemporaryFile helper {
				get;
				private set;
			}

			private HashMap<string, TemporaryFile> agents = new HashMap<string, TemporaryFile> ();

			public ResourceStore () throws IOError {
				tempdir = new TemporaryDirectory ();
				var blob = Frida.Data.Fruitjector.get_frida_fruitjector_helper_blob ();
				helper = new TemporaryFile.from_stream ("frida-fruitjector-helper",
					new MemoryInputStream.from_data (blob.data, null),
					tempdir);
			}

			~ResourceStore () {
				foreach (var tempfile in agents.values)
					tempfile.destroy ();
				tempdir.destroy ();
			}

			public string ensure_copy_of (AgentDescriptor desc) throws IOError {
				var temp_agent = agents[desc.name];
				if (temp_agent == null) {
					temp_agent = new TemporaryFile.from_stream (desc.name, desc.dylib, tempdir);
					agents[desc.name] = temp_agent;
				}
				return temp_agent.path;
			}
		}
	}

	public class AgentDescriptor : Object {
		public string name {
			get;
			construct;
		}

		public InputStream dylib {
			get {
				reset_stream (_dylib);
				return _dylib;
			}

			construct {
				_dylib = value;
			}
		}
		private InputStream _dylib;

		public AgentDescriptor (string name, InputStream dylib) {
			Object (name: name, dylib: dylib);

			assert (dylib is Seekable);
		}

		private void reset_stream (InputStream stream) {
			try {
				(stream as Seekable).seek (0, SeekType.SET);
			} catch (Error e) {
				assert_not_reached ();
			}
		}
	}
}
#endif