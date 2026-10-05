"""
StageDeck extension for AbletonOSC: master track, cue volume and return tracks.

Upstream AbletonOSC only exposes song.tracks; the master and return tracks live in
song.master_track / song.return_tracks. This handler follows the same conventions:

    /live/master/get/volume                         -> volume
    /live/master/set/volume <value>
    /live/master/start_listen/volume                -> pushes /live/master/get/volume <value>
    /live/master/get|set|start_listen/panning
    /live/master/get|set|start_listen/cue_volume
    /live/master/get|start_listen/output_meter_level
    /live/master/get|start_listen/output_meter_left
    /live/master/get|start_listen/output_meter_right

    /live/song/get/num_return_tracks                -> count
    /live/song/get/return_tracks/name               -> name, name, ...
    /live/return/get|set/volume <index> [<value>]   -> index, value
    /live/return/get|set/mute <index> [<value>]
    /live/return/get|set/panning <index> [<value>]
    /live/return/start_listen|stop_listen/<volume|mute|panning|output_meter_level> <index>
    /live/return/get|set/send <index> <send> [<value>]    -> index, send, value
    /live/return/start_listen|stop_listen/send <index> <send>

Devices on the master and on return tracks (upstream only covers song.tracks):

    /live/master/get/num_devices                    -> count
    /live/master/get/devices/name                   -> name, name, ...
    /live/master/get/devices/class_name             -> class, class, ...
    /live/master/device/get/parameters/name|value|min|max <device>      -> device, ...
    /live/master/device/get/parameter/value <device> <param>            -> device, param, value
    /live/master/device/set/parameter/value <device> <param> <value>
    /live/master/device/start_listen|stop_listen/parameter/value <device> <param>
    /live/return/get/num_devices <index>, /live/return/get/devices/name|class_name <index>
    /live/return/device/... <index> <device> ...     (same as master, with the return index first)
"""
from typing import Tuple, Any, Optional
from .handler import AbletonOSCHandler


class MasterHandler(AbletonOSCHandler):
    def __init__(self, manager):
        super().__init__(manager)
        self.class_identifier = "master"

    def init_api(self):
        master = self.song.master_track

        # --- Master mixer parameters (volume, panning, cue_volume) -------------------------
        for prop in ["volume", "panning", "cue_volume"]:
            self.osc_server.add_handler("/live/master/get/%s" % prop,
                                        self._make_mixer_get(master, prop))
            self.osc_server.add_handler("/live/master/set/%s" % prop,
                                        self._make_mixer_set(master, prop))
            self.osc_server.add_handler("/live/master/start_listen/%s" % prop,
                                        self._make_mixer_listen(master, prop, "master", ()))
            self.osc_server.add_handler("/live/master/stop_listen/%s" % prop,
                                        self._make_mixer_unlisten(master, prop, ()))

        # --- Master meters (read-only, listenable) -----------------------------------------
        for prop in ["output_meter_level", "output_meter_left", "output_meter_right"]:
            self.osc_server.add_handler("/live/master/get/%s" % prop,
                                        lambda params, prop=prop: self._get_property(master, prop, ()))
            self.osc_server.add_handler("/live/master/start_listen/%s" % prop,
                                        lambda params, prop=prop: self._start_listen(master, prop, ()))
            self.osc_server.add_handler("/live/master/stop_listen/%s" % prop,
                                        lambda params, prop=prop: self._stop_listen(master, prop, ()))

        # --- Return tracks ---------------------------------------------------------------
        self.osc_server.add_handler("/live/song/get/num_return_tracks",
                                    lambda _: (len(self.song.return_tracks),))
        self.osc_server.add_handler("/live/song/get/return_tracks/name",
                                    lambda _: tuple(t.name for t in self.song.return_tracks))

        def make_return_callback(func):
            def callback(params: Tuple[Any]):
                index = int(params[0])
                track = self.song.return_tracks[index]
                rv = func(track, index, tuple(params[1:]))
                if rv is not None:
                    return (index, *rv)
            return callback

        def return_get_mixer(prop):
            def f(track, index, params):
                return (getattr(track.mixer_device, prop).value,)
            return f

        def return_set_mixer(prop):
            def f(track, index, params):
                getattr(track.mixer_device, prop).value = params[0]
            return f

        def return_get_mute(track, index, params):
            return (track.mute,)

        def return_set_mute(track, index, params):
            track.mute = params[0]

        for prop in ["volume", "panning"]:
            self.osc_server.add_handler("/live/return/get/%s" % prop, make_return_callback(return_get_mixer(prop)))
            self.osc_server.add_handler("/live/return/set/%s" % prop, make_return_callback(return_set_mixer(prop)))
        self.osc_server.add_handler("/live/return/get/mute", make_return_callback(return_get_mute))
        self.osc_server.add_handler("/live/return/set/mute", make_return_callback(return_set_mute))

        def return_listen(prop, start):
            def callback(params: Tuple[Any]):
                index = int(params[0])
                track = self.song.return_tracks[index]
                if prop in ("volume", "panning"):
                    if start:
                        self._make_mixer_listen(track, prop, "return", (index,))(params)
                    else:
                        self._make_mixer_unlisten(track, prop, (index,))(params)
                else:
                    if start:
                        self._start_listen_as(track, prop, "return", (index,))
                    else:
                        self._stop_listen(track, prop, (index,))
            return callback

        for prop in ["volume", "panning", "mute", "output_meter_level"]:
            self.osc_server.add_handler("/live/return/start_listen/%s" % prop, return_listen(prop, True))
            self.osc_server.add_handler("/live/return/stop_listen/%s" % prop, return_listen(prop, False))

        # --- Return sends (a return can feed the other returns) -----------------------------
        def return_get_send(track, index, params):
            s = int(params[0])
            return (s, track.mixer_device.sends[s].value)

        def return_set_send(track, index, params):
            track.mixer_device.sends[int(params[0])].value = params[1]

        self.osc_server.add_handler("/live/return/get/send", make_return_callback(return_get_send))
        self.osc_server.add_handler("/live/return/set/send", make_return_callback(return_set_send))

        def return_send_listen(start):
            def callback(params: Tuple[Any]):
                index = int(params[0])
                s = int(params[1])
                parameter_object = self.song.return_tracks[index].mixer_device.sends[s]
                listener_key = ("send", index, s)
                if listener_key in self.listener_functions:
                    try:
                        parameter_object.remove_value_listener(self.listener_functions[listener_key])
                    except Exception:
                        pass
                    del self.listener_functions[listener_key]
                    self.listener_objects.pop(listener_key, None)
                if start:
                    def changed():
                        self.osc_server.send("/live/return/get/send", (index, s, parameter_object.value))
                    parameter_object.add_value_listener(changed)
                    self.listener_functions[listener_key] = changed
                    self.listener_objects[listener_key] = parameter_object
                    changed()
            return callback

        self.osc_server.add_handler("/live/return/start_listen/send", return_send_listen(True))
        self.osc_server.add_handler("/live/return/stop_listen/send", return_send_listen(False))

        # --- Devices on the master and on returns -------------------------------------------
        self.osc_server.add_handler("/live/master/get/num_devices", lambda _: (len(master.devices),))
        self.osc_server.add_handler("/live/master/get/devices/name", lambda _: tuple(d.name for d in master.devices))
        self.osc_server.add_handler("/live/master/get/devices/class_name", lambda _: tuple(d.class_name for d in master.devices))
        self.osc_server.add_handler("/live/return/get/num_devices", make_return_callback(lambda t, i, p: (len(t.devices),)))
        self.osc_server.add_handler("/live/return/get/devices/name", make_return_callback(lambda t, i, p: tuple(d.name for d in t.devices)))
        self.osc_server.add_handler("/live/return/get/devices/class_name", make_return_callback(lambda t, i, p: tuple(d.class_name for d in t.devices)))

        self._install_device_api("/live/master/device", lambda params: (master, (), tuple(params)))
        self._install_device_api("/live/return/device",
                                 lambda params: (self.song.return_tracks[int(params[0])], (int(params[0]),), tuple(params[1:])))

    # ------------------------------------------------------------------------------------
    # Device API shared by master and returns (mirrors upstream /live/device/…)
    # ------------------------------------------------------------------------------------
    def _install_device_api(self, prefix, resolve):
        """resolve(params) -> (track, ids, rest). ids are echoed first in every reply;
        rest[0] is the device index, rest[1:] the remaining arguments."""
        def handler(func):
            def callback(params: Tuple[Any]):
                track, ids, rest = resolve(params)
                device_index = int(rest[0])
                device = track.devices[device_index]
                rv = func(device, ids + (device_index,), tuple(rest[1:]))
                if rv is not None:
                    return (*ids, device_index, *rv)
            return callback

        def get_names(device, ids, p):
            return tuple(x.name for x in device.parameters)

        def get_values(device, ids, p):
            return tuple(x.value for x in device.parameters)

        def get_mins(device, ids, p):
            return tuple(x.min for x in device.parameters)

        def get_maxes(device, ids, p):
            return tuple(x.max for x in device.parameters)

        def get_value(device, ids, p):
            i = int(p[0])
            return (i, device.parameters[i].value)

        def set_value(device, ids, p):
            device.parameters[int(p[0])].value = p[1]

        def stop_listen(device, ids, p):
            i = int(p[0])
            key = ("device_parameter_value", prefix, ids, i)
            fn = self.listener_functions.pop(key, None)
            obj = self.listener_objects.pop(key, None)
            if fn is not None and obj is not None:
                try:
                    obj.remove_value_listener(fn)
                except Exception:
                    pass

        def start_listen(device, ids, p):
            i = int(p[0])
            stop_listen(device, ids, p)
            parameter_object = device.parameters[i]
            key = ("device_parameter_value", prefix, ids, i)

            def changed():
                self.osc_server.send(prefix + "/get/parameter/value", (*ids, i, parameter_object.value))

            parameter_object.add_value_listener(changed)
            self.listener_functions[key] = changed
            self.listener_objects[key] = parameter_object
            changed()

        self.osc_server.add_handler(prefix + "/get/parameters/name", handler(get_names))
        self.osc_server.add_handler(prefix + "/get/parameters/value", handler(get_values))
        self.osc_server.add_handler(prefix + "/get/parameters/min", handler(get_mins))
        self.osc_server.add_handler(prefix + "/get/parameters/max", handler(get_maxes))
        self.osc_server.add_handler(prefix + "/get/parameter/value", handler(get_value))
        self.osc_server.add_handler(prefix + "/set/parameter/value", handler(set_value))
        self.osc_server.add_handler(prefix + "/start_listen/parameter/value", handler(start_listen))
        self.osc_server.add_handler(prefix + "/stop_listen/parameter/value", handler(stop_listen))

    # ------------------------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------------------------
    def _make_mixer_get(self, track, prop):
        def callback(params: Tuple[Any] = ()):
            return (getattr(track.mixer_device, prop).value,)
        return callback

    def _make_mixer_set(self, track, prop):
        def callback(params: Tuple[Any]):
            getattr(track.mixer_device, prop).value = params[0]
        return callback

    def _make_mixer_listen(self, track, prop, identifier, ids):
        def callback(params: Tuple[Any] = ()):
            parameter_object = getattr(track.mixer_device, prop)
            listener_key = (prop, tuple(ids))

            def property_changed_callback():
                value = parameter_object.value
                self.osc_server.send("/live/%s/get/%s" % (identifier, prop), (*ids, value))

            if listener_key in self.listener_functions:
                parameter_object.remove_value_listener(self.listener_functions[listener_key])
                del self.listener_functions[listener_key]
            parameter_object.add_value_listener(property_changed_callback)
            self.listener_functions[listener_key] = property_changed_callback
            self.listener_objects[listener_key] = parameter_object
            property_changed_callback()
        return callback

    def _make_mixer_unlisten(self, track, prop, ids):
        def callback(params: Tuple[Any] = ()):
            parameter_object = getattr(track.mixer_device, prop)
            listener_key = (prop, tuple(ids))
            if listener_key in self.listener_functions:
                try:
                    parameter_object.remove_value_listener(self.listener_functions[listener_key])
                except Exception:
                    pass
                del self.listener_functions[listener_key]
                self.listener_objects.pop(listener_key, None)
        return callback

    def _start_listen_as(self, target, prop, identifier, params):
        """Like AbletonOSCHandler._start_listen but with an explicit OSC identifier."""
        def property_changed_callback():
            value = getattr(target, prop)
            if type(value) is not tuple:
                value = (value,)
            self.osc_server.send("/live/%s/get/%s" % (identifier, prop), (*params, *value))

        listener_key = (prop, tuple(params))
        if listener_key in self.listener_functions:
            self._stop_listen(target, prop, params)
        getattr(target, "add_%s_listener" % prop)(property_changed_callback)
        self.listener_functions[listener_key] = property_changed_callback
        self.listener_objects[listener_key] = target
        property_changed_callback()

    def clear_api(self):
        # Mixer listeners are stored against DeviceParameter objects; remove them explicitly.
        for key in list(self.listener_functions.keys()):
            obj = self.listener_objects.get(key)
            fn = self.listener_functions[key]
            try:
                if hasattr(obj, "remove_value_listener"):
                    obj.remove_value_listener(fn)
                    del self.listener_functions[key]
                    del self.listener_objects[key]
            except Exception:
                pass
        super().clear_api()
