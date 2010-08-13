namespace Zed {
	public class View.ProcessSelector : Gtk.HBox {
		public Gtk.ComboBoxEntry combo {
			get;
			private set;
		}

		public Gtk.Entry entry {
			get {
				return combo.get_child () as Gtk.Entry;
			}
		}

		public void set_model (Gtk.TreeModel process_model) {
			assert (combo == null);

			combo = new Gtk.ComboBoxEntry.with_model (process_model, 0);
			pack_start (combo, false, false, 0);

			show_all ();
		}
	}

	public class Presenter.ProcessSelector : Object {
		public View.ProcessSelector view {
			get;
			construct;
		}

		public HostSession session {
			get;
			set;
		}

		private Gtk.ListStore process_store = new Gtk.ListStore (2, typeof (string), typeof (ProcessInfo));

		public ProcessSelector (View.ProcessSelector view) {
			Object (view: view);

			process_store.set_sort_column_id (0, Gtk.SortType.ASCENDING);

			view.set_model (process_store);

			configure_entry ();
		}

		private void configure_entry () {
			var entry = view.entry;

			var completion = new Gtk.EntryCompletion ();

			completion.set_model (process_store);
			completion.set_popup_completion (true);

			var icon_renderer = new Gtk.CellRendererPixbuf ();
			completion.pack_start (icon_renderer, false);
			completion.set_cell_data_func (icon_renderer, entry_completion_data_callback);

			completion.set_text_column (0);

			var pid_renderer = new Gtk.CellRendererText ();
			completion.pack_end (pid_renderer, false);
			completion.set_cell_data_func (pid_renderer, entry_completion_data_callback);

			completion.match_selected.connect ((model, iter) => {
				ProcessInfo pi;
				model.get (iter, 1, out pi);
				entry.set_text (pi.pid.to_string ());
				entry.move_cursor (Gtk.MovementStep.BUFFER_ENDS, 1, false);
				return true;
			});

			entry.set_completion (completion);
		}

		private void entry_completion_data_callback (Gtk.CellLayout layout, Gtk.CellRenderer renderer, Gtk.TreeModel model, Gtk.TreeIter iter) {
			ProcessInfo pi;
			model.get (iter, 1, out pi);

			if (renderer is Gtk.CellRendererPixbuf)
				(renderer as Gtk.CellRendererPixbuf).pixbuf = pi.small_icon;
			else
				(renderer as Gtk.CellRendererText).text = pi.pid.to_string ();
		}
	}

	// FIXME: move ProcessInfo here

	/*
			pe.focus_in_event.connect ((event) => {
				if (process_list.time_since_last_update () >= PROCESS_LIST_MIN_UPDATE_INTERVAL)
					process_list.update ();
				return false;
			});
	*/
}