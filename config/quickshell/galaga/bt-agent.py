#!/usr/bin/env python3
# galaga's bluetooth pairing agent.
#
# quickshell registers no agent with bluez, and without an agent
# anywhere bluez never completes a bond: an unpaired device
# "connects" as a bare radio link -- no audio profile, nothing
# stored -- and falls back to "tap to pair" when it disconnects
# (proven on-machine 2026-11-18: the ui alone never bonded a pair
# of buds; the same taps with bluetoothctl running, its agent
# registered, bonded them at once; a scripted bluetoothctl does
# not help -- it exits and takes its agent with it).
#
# So the shell runs its own. This registers org.bluez.Agent1 with
# the NoInputNoOutput capability and accepts every request, the
# just-works behaviour buds, mice and speakers expect. The known
# limit of a no-input agent: a device that must show a passkey for
# you to type, or read one you type (some keyboards), cannot pair
# through it.
#
# It re-registers whenever org.bluez (re)appears, so restarting the
# bluetooth service does not silently kill pairing until the next
# login. The shell supervises the process (services/BtAgent.qml).
# GALAGA_BT_AGENT_BUS=session exists for the sandbox mock test;
# production uses the system bus.

import os
import sys

from gi.repository import Gio, GLib

AGENT_PATH = "/org/galaga/BtAgent"
CAPABILITY = "NoInputNoOutput"
BLUEZ = "org.bluez"
MANAGER_PATH = "/org/bluez"
MANAGER_IFACE = "org.bluez.AgentManager1"

AGENT_XML = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode">
      <arg name="device" type="o" direction="in"/>
      <arg name="pincode" type="s" direction="out"/>
    </method>
    <method name="DisplayPinCode">
      <arg name="device" type="o" direction="in"/>
      <arg name="pincode" type="s" direction="in"/>
    </method>
    <method name="RequestPasskey">
      <arg name="device" type="o" direction="in"/>
      <arg name="passkey" type="u" direction="out"/>
    </method>
    <method name="DisplayPasskey">
      <arg name="device" type="o" direction="in"/>
      <arg name="passkey" type="u" direction="in"/>
      <arg name="entered" type="q" direction="in"/>
    </method>
    <method name="RequestConfirmation">
      <arg name="device" type="o" direction="in"/>
      <arg name="passkey" type="u" direction="in"/>
    </method>
    <method name="RequestAuthorization">
      <arg name="device" type="o" direction="in"/>
    </method>
    <method name="AuthorizeService">
      <arg name="device" type="o" direction="in"/>
      <arg name="uuid" type="s" direction="in"/>
    </method>
    <method name="Cancel"/>
  </interface>
</node>
"""


def on_method(conn, sender, path, iface, method, params, invocation):
    # every request is accepted: the two that ask for a secret get
    # the defaults legacy devices fall back to, the rest are yes by
    # returning an empty reply.
    if method == "RequestPinCode":
        invocation.return_value(GLib.Variant("(s)", ("0000",)))
    elif method == "RequestPasskey":
        invocation.return_value(GLib.Variant("(u)", (0,)))
    else:
        invocation.return_value(None)


def register(conn):
    try:
        conn.call_sync(BLUEZ, MANAGER_PATH, MANAGER_IFACE, "RegisterAgent",
                       GLib.Variant("(os)", (AGENT_PATH, CAPABILITY)),
                       None, Gio.DBusCallFlags.NONE, -1, None)
    except GLib.Error as e:
        # already registered (a retry raced itself) is success;
        # anything else is reported by the caller retrying later
        if "AlreadyExists" not in e.message:
            return False
    try:
        conn.call_sync(BLUEZ, MANAGER_PATH, MANAGER_IFACE,
                       "RequestDefaultAgent",
                       GLib.Variant("(o)", (AGENT_PATH,)),
                       None, Gio.DBusCallFlags.NONE, -1, None)
    except GLib.Error:
        pass  # being registered is what pairing needs; default is a bonus
    print("bt-agent: registered with bluez", file=sys.stderr, flush=True)
    return True


def main():
    bus_type = (Gio.BusType.SESSION
                if os.environ.get("GALAGA_BT_AGENT_BUS") == "session"
                else Gio.BusType.SYSTEM)
    conn = Gio.bus_get_sync(bus_type, None)
    node = Gio.DBusNodeInfo.new_for_xml(AGENT_XML)
    conn.register_object(AGENT_PATH, node.interfaces[0], on_method, None)

    # register now if bluez is already up, and again every time it
    # (re)appears -- its registrations die with it
    register(conn)

    def on_owner_changed(c, sender, path, iface, signal, params, user_data):
        name, old_owner, new_owner = params.unpack()
        if name == BLUEZ and new_owner:
            register(c)

    conn.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus",
                          "NameOwnerChanged", "/org/freedesktop/DBus",
                          BLUEZ, Gio.DBusSignalFlags.NONE,
                          on_owner_changed, None)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
