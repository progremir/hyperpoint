#!/usr/bin/env python3
"""Checks a Hyperpoint config file the way the app's parser does, before the app sees it.

    python3 check_config.py [path]          # default ~/.config/hyperpoint/config.json

Prints the devices it found, or the first problem with its path (such as devices[1].rules[0].when), which is the
path the app's menu would show. Exits 0 when the app would accept the file, 1 when it would reject it, 2 when the
file cannot be read. It mirrors Sources/HyperpointKit/Model/ConfigCodec.swift; the app stays the judge.
"""

import json
import os
import sys

DEFAULT_PATH = os.path.expanduser("~/.config/hyperpoint/config.json")

KEYS = (
    "a b c d e f g h i j k l m n o p q r s t u v w x y z 1 2 3 4 5 6 7 8 9 0 return escape delete tab space minus "
    "equal leftBracket rightBracket backslash semicolon quote grave comma period slash capsLock f1 f2 f3 f4 f5 f6 f7 "
    "f8 f9 f10 f11 f12 home pageUp forwardDelete end pageDown right left down up"
).split()
KEY_NAMES = {name.lower() for name in KEYS}
MODIFIER_NAMES = {"ctrl", "control", "opt", "option", "alt", "shift", "cmd", "command"}
HELD_MODIFIERS = {
    "leftControl", "leftShift", "leftOption", "leftCommand",
    "rightControl", "rightShift", "rightOption", "rightCommand",
}
SYSTEM_ACTIONS = {"missionControl", "appExpose", "spaceLeft", "spaceRight"}
DIRECTIONS = ("Up", "Down", "Left", "Right")
TRIGGERS = {"click", "hold", "holdMove", "scroll"} | {"holdMove" + d for d in DIRECTIONS}

# Which triggers each kind of control takes, and which actions each trigger may do. "swipe" is hold and move one
# way, "holdMove" hold and move any way.
RULE_TABLE = {
    "hidpp": {"click": {"system", "shortcut"}, "swipe": {"system", "shortcut"}, "holdMove": {"scroll"}},
    "thumbWheel": {"scroll": {"reverse"}},
    "key": {"click": {"shortcut"}, "hold": {"modifier"}},
    "button": {"click": {"system", "shortcut"}, "holdMove": {"scroll"}},
}


class Problem(Exception):
    def __init__(self, path, message):
        super().__init__(message)
        self.path = path
        self.message = message

    def __str__(self):
        return f"{self.path}: {self.message}" if self.path else self.message


def join(path, key):
    if isinstance(key, int):
        return f"{path}[{key}]"
    return f"{path}.{key}" if path else key


def g(number):
    """A number as Swift's %g writes it."""
    return f"{number:g}"


# Decoding, in the order the app's decoder reads fields, so the first problem is the one the app reports.

def obj(value, path):
    if not isinstance(value, dict):
        raise Problem(path, "expected an object")
    return value


def expect(value, path, kind):
    checks = {
        "a string": lambda v: isinstance(v, str),
        "true or false": lambda v: isinstance(v, bool),
        "a number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
        "a list": lambda v: isinstance(v, list),
    }
    if not checks[kind](value):
        raise Problem(path, f"expected {kind}")
    return value


def whole(value, path):
    expect(value, path, "a number")
    if value != int(value):
        raise Problem(path, f"Parsed JSON number <{value}> does not fit in Int.")
    return int(value)


def required(section, key, path):
    if key not in section:
        raise Problem(join(path, key), "missing key")
    if section[key] is None:
        raise Problem(join(path, key), "expected a value")
    return section[key]


def optional(section, key):
    return section.get(key)


def one_of(value, path, allowed, what):
    expect(value, path, "a string")
    if value not in allowed:
        raise Problem(path, f'"{value}" is not a valid {what}. Use one of: {", ".join(sorted(allowed))}')
    return value


def hex_id(value, path):
    expect(value, path, "a string")
    digits = value[2:]
    if value[:2] not in ("0x", "0X") or not digits or any(c not in "0123456789abcdefABCDEF" for c in digits) \
            or int(digits, 16) > 0xFFFF:
        raise Problem(path, f'"{value}" is not a hex id such as "0x046D"')
    return int(digits, 16)


def key_name(value, path):
    expect(value, path, "a string")
    if value.lower() not in KEY_NAMES:
        raise Problem(path, f'unknown key "{value}"')
    return value.lower()


def decode_match(value, path):
    obj(value, path)
    if value.get("builtIn") is not None:
        built_in = expect(value["builtIn"], join(path, "builtIn"), "true or false")
        if not built_in or "vendor" in value or "product" in value:
            raise Problem(join(path, "builtIn"), 'write {"builtIn": true} alone, or a vendor and product instead')
        return ("builtIn",)
    vendor = hex_id(required(value, "vendor", path), join(path, "vendor"))
    product = hex_id(required(value, "product", path), join(path, "product"))
    return ("device", vendor, product)


def decode_control(value, path):
    if isinstance(value, str):
        if value != "thumbWheel":
            raise Problem(path, f'unknown control "{value}"')
        return ("thumbWheel",)
    obj(value, path)
    present = [key for key in ("hidpp", "key", "button") if key in value]
    if len(present) != 1:
        raise Problem(path, 'a control is "thumbWheel" or one of {"hidpp"}, {"key"}, {"button"}')
    kind = present[0]
    inner = required(value, kind, path)
    if kind == "hidpp":
        return ("hidpp", hex_id(inner, join(path, "hidpp")))
    if kind == "key":
        return ("key", key_name(inner, join(path, "key")))
    return ("button", whole(inner, join(path, "button")))


def decode_trigger(value, path):
    expect(value, path, "a string")
    if value not in TRIGGERS:
        raise Problem(path, f'unknown trigger "{value}"')
    return value


def decode_chord(value, path):
    expect(value, path, "a string")
    tokens = value.split("+")
    if tokens[-1].lower() not in KEY_NAMES:
        raise Problem(path, f'"{value}" does not end in a key name such as "s" or "4"')
    for token in tokens[:-1]:
        if token.lower() not in MODIFIER_NAMES:
            raise Problem(path, f'unknown modifier "{token}" in "{value}"')
    return value.lower()


def decode_action(value, path):
    if isinstance(value, str):
        if value in ("reverse", "scroll"):
            return (value,)
        if value in SYSTEM_ACTIONS:
            return ("system", value)
        raise Problem(path, f'unknown action "{value}"')
    obj(value, path)
    present = [key for key in ("shortcut", "modifier") if key in value]
    if len(present) != 1:
        raise Problem(path, 'an action is a name such as "missionControl", or {"shortcut"} or {"modifier"}')
    kind = present[0]
    inner = required(value, kind, path)
    if kind == "shortcut":
        return ("shortcut", decode_chord(inner, join(path, "shortcut")))
    return ("modifier", one_of(inner, join(path, "modifier"), HELD_MODIFIERS, "modifier"))


def decode_rule(value, path):
    obj(value, path)
    return {
        "control": decode_control(required(value, "control", path), join(path, "control")),
        "when": decode_trigger(required(value, "when", path), join(path, "when")),
        "do": decode_action(required(value, "do", path), join(path, "do")),
    }


def decode_curve(value, path):
    expect(value, path, "a list")
    points = []
    for index, point in enumerate(value):
        point_path = join(path, index)
        obj(point, point_path)
        points.append((
            expect(required(point, "stepsPerSecond", point_path), join(point_path, "stepsPerSecond"), "a number"),
            expect(required(point, "pointsPerSecond", point_path), join(point_path, "pointsPerSecond"), "a number"),
        ))
    if len(points) < 2:
        raise Problem(path, "needs at least 2 points")
    for index, (rate, speed) in enumerate(points):
        point_path = join(path, index)
        if not 1 <= rate <= 150:
            raise Problem(join(point_path, "stepsPerSecond"), "must be between 1 and 150")
        if not 10 <= speed <= 30_000:
            raise Problem(join(point_path, "pointsPerSecond"), "must be between 10 and 30000")
        if index > 0 and rate <= points[index - 1][0]:
            raise Problem(join(point_path, "stepsPerSecond"), "must be more than the point before")
        if index > 0 and speed < points[index - 1][1]:
            raise Problem(join(point_path, "pointsPerSecond"), "must be at least the point before")
    return points


def decode_smooth(value, path):
    obj(value, path)
    smooth = {
        "duration": expect(required(value, "duration", path), join(path, "duration"), "a number"),
        "brake": expect(required(value, "brake", path), join(path, "brake"), "a number"),
        "easeIn": 60,
    }
    if optional(value, "easeIn") is not None:
        smooth["easeIn"] = expect(value["easeIn"], join(path, "easeIn"), "a number")
    if optional(value, "curve") is not None:
        decode_curve(value["curve"], join(path, "curve"))
    else:
        # Files from before the speed curve: these keys convert to one.
        acceleration = optional(value, "acceleration")
        if acceleration is not None and not isinstance(acceleration, bool):
            acceleration_path = join(path, "acceleration")
            obj(acceleration, acceleration_path)
            for key in ("from", "to", "max"):
                expect(required(acceleration, key, acceleration_path), join(acceleration_path, key), "a number")
        for key in ("speed", "startBoost"):
            if optional(value, key) is not None:
                expect(value[key], join(path, key), "a number")
    return smooth


def decode_scrolling(value, path):
    obj(value, path)
    scrolling = {}
    if optional(value, "smooth") is not None:
        scrolling["smooth"] = decode_smooth(value["smooth"], join(path, "smooth"))
    if optional(value, "hiResWheel") is not None:
        expect(value["hiResWheel"], join(path, "hiResWheel"), "true or false")
    if optional(value, "holdToScroll") is not None:
        hold_path = join(path, "holdToScroll")
        hold = obj(value["holdToScroll"], hold_path)
        scrolling["holdToScroll"] = {
            "speed": expect(required(hold, "speed", hold_path), join(hold_path, "speed"), "a number"),
        }
        one_of(required(hold, "direction", hold_path), join(hold_path, "direction"), {"grab", "wheel"}, "direction")
        expect(required(hold, "momentum", hold_path), join(hold_path, "momentum"), "true or false")
    if optional(value, "clickThrough") is not None:
        click_path = join(path, "clickThrough")
        click = obj(value["clickThrough"], click_path)
        for key in ("left", "right"):
            expect(required(click, key, click_path), join(click_path, key), "true or false")
    return scrolling


def decode_profile(value, path):
    obj(value, path)
    profile = {
        "match": decode_match(required(value, "match", path), join(path, "match")),
        "name": expect(required(value, "name", path), join(path, "name"), "a string"),
        "kind": None,
        "rules": [],
        "gestures": None,
        "scrolling": {},
        "hyper": False,
    }
    if optional(value, "kind") is not None:
        profile["kind"] = one_of(value["kind"], join(path, "kind"), {"mouse", "keyboard"}, "kind")
    if optional(value, "rules") is not None:
        rules_path = join(path, "rules")
        expect(value["rules"], rules_path, "a list")
        profile["rules"] = [decode_rule(rule, join(rules_path, i)) for i, rule in enumerate(value["rules"])]
    if optional(value, "gestures") is not None:
        gestures_path = join(path, "gestures")
        gestures = obj(value["gestures"], gestures_path)
        one_of(required(gestures, "fire", gestures_path), join(gestures_path, "fire"), {"pastDistance", "onRelease"},
               "fire")
        profile["gestures"] = {
            "distance": whole(required(gestures, "distance", gestures_path), join(gestures_path, "distance")),
        }
    if optional(value, "scrolling") is not None:
        profile["scrolling"] = decode_scrolling(value["scrolling"], join(path, "scrolling"))
    if optional(value, "hyper") is not None:
        profile["hyper"] = expect(value["hyper"], join(path, "hyper"), "true or false")
    # Files from before hold to scroll: right-button pan becomes a hold-and-move scroll rule on the right button.
    pan = value["scrolling"].get("rightButtonPan") if isinstance(value.get("scrolling"), dict) else None
    if pan is not None:
        pan_path = join(join(path, "scrolling"), "rightButtonPan")
        expect(required(obj(pan, pan_path), "momentum", pan_path), join(pan_path, "momentum"), "true or false")
        rule = {"control": ("button", 1), "when": "holdMove", "do": ("scroll",)}
        if not any(r["control"] == rule["control"] and r["when"] == rule["when"] for r in profile["rules"]):
            profile["rules"].append(rule)
    return profile


def decode(tree):
    obj(tree, "")
    config = {"version": whole(required(tree, "version", ""), "version")}
    hyper = obj(required(tree, "hyper", ""), "hyper")
    if optional(hyper, "enabled") is not None:
        expect(hyper["enabled"], "hyper.enabled", "true or false")
    key_name(required(hyper, "key", "hyper"), "hyper.key")
    one_of(required(hyper, "onTap", "hyper"), "hyper.onTap", {"nothing"}, "onTap")
    expect(required(tree, "devices", ""), "devices", "a list")
    config["devices"] = [decode_profile(p, join("devices", i)) for i, p in enumerate(tree["devices"])]
    expect(required(tree, "ignored", ""), "ignored", "a list")
    config["ignored"] = [decode_match(m, join("ignored", i)) for i, m in enumerate(tree["ignored"])]
    return config


# Unknown keys and nulls, checked like the app: every key in sorted order, depth first.

def schema(tree):
    """The keys the app knows at each place in this file, shaped like the file."""
    def match(m):
        return {"builtIn": True} if m.get("builtIn") is not None else {"vendor": 0, "product": 0}

    def control(c):
        return {k: 0 for k in ("hidpp", "key", "button") if k in c} if isinstance(c, dict) else c

    def action(a):
        return {k: 0 for k in ("shortcut", "modifier") if k in a} if isinstance(a, dict) else a

    def scrolling(s):
        known = {
            "smooth": {"duration": 0, "brake": 0, "easeIn": 0, "curve": [
                {"stepsPerSecond": 0, "pointsPerSecond": 0} for _ in (s.get("smooth") or {}).get("curve") or []
            ]},
            "hiResWheel": 0,
            "holdToScroll": {"speed": 0, "direction": 0, "momentum": 0},
            "clickThrough": {"left": 0, "right": 0},
        }
        if "curve" not in (s.get("smooth") or {}):
            known["smooth"].update({"speed": 0, "startBoost": 0, "acceleration": {"from": 0, "to": 0, "max": 0}})
        known["rightButtonPan"] = {"momentum": 0}
        return known

    devices = []
    for profile in tree["devices"]:
        devices.append({
            "match": match(profile["match"]),
            "name": 0,
            "kind": 0,
            "rules": [{"control": control(r["control"]), "when": 0, "do": action(r["do"])}
                      for r in profile.get("rules") or []],
            "gestures": {"fire": 0, "distance": 0},
            "scrolling": scrolling(profile.get("scrolling") or {}),
            "hyper": 0,
        })
    return {
        "version": 0,
        "hyper": {"enabled": 0, "key": 0, "onTap": 0},
        "devices": devices,
        "ignored": [match(m) for m in tree["ignored"]],
    }


def unknown_key(user, known, path):
    if isinstance(user, dict) and isinstance(known, dict):
        for key in sorted(user):
            child = join(path, key)
            if user[key] is None:
                raise Problem(child, "null is not allowed. Leave the key out instead")
            if key not in known:
                raise Problem(child, "unknown key")
            unknown_key(user[key], known[key], child)
    elif isinstance(user, list) and isinstance(known, list):
        for index, (item, known_item) in enumerate(zip(user, known)):
            unknown_key(item, known_item, join(path, index))


# The checks that need the whole file.

def trigger_kind(trigger):
    if trigger == "holdMove":
        return "holdMove"
    return "swipe" if trigger.startswith("holdMove") else trigger


def action_kind(action):
    return action[0]


def conflict(trigger, other):
    pair = {trigger_kind(trigger), trigger_kind(other)}
    if pair == {"holdMove", "swipe"}:
        return "scrolling and swipes both use the movement"
    if pair == {"click", "hold"}:
        return "a key held as a modifier becomes that modifier, so it has no click of its own"
    return None


def validate(config):
    if config["version"] != 1:
        raise Problem("version", f"version {config['version']} is not supported")
    for index, profile in enumerate(config["devices"]):
        path = join("devices", index)
        earlier = [p["match"] for p in config["devices"][:index]]
        if profile["match"] in earlier:
            raise Problem(join(path, "match"), f"the same device as devices[{earlier.index(profile['match'])}]")
        if profile["match"] in config["ignored"]:
            raise Problem(join(path, "match"), "this device is also in ignored")
        gestures = profile["gestures"]
        if gestures and not 20 <= gestures["distance"] <= 2000:
            raise Problem(join(path, "gestures.distance"), "must be between 20 and 2000")
        hold = profile["scrolling"].get("holdToScroll")
        if hold and not 0.25 <= hold["speed"] <= 4:
            raise Problem(join(path, "scrolling.holdToScroll.speed"), "must be between 0.25 and 4")
        smooth = profile["scrolling"].get("smooth")
        if smooth:
            for key, low, high in (("duration", 1, 20), ("brake", 0.5, 10), ("easeIn", 0, 300)):
                if not low <= smooth[key] <= high:
                    raise Problem(join(path, f"scrolling.smooth.{key}"), f"must be between {g(low)} and {g(high)}")
        rules = profile["rules"]
        for rule_index, rule in enumerate(rules):
            rule_path = join(join(path, "rules"), rule_index)
            control, trigger = rule["control"], rule["when"]
            if control[0] == "button" and not 1 <= control[1] <= 31:
                raise Problem(join(rule_path, "control.button"),
                              "must be between 1 and 31. 1 is the right button, and the left button, 0, cannot have rules")
            actions = RULE_TABLE[control[0]].get(trigger_kind(trigger))
            if actions is None:
                raise Problem(join(rule_path, "when"), f'"{trigger}" does not work with this control')
            if action_kind(rule["do"]) not in actions:
                raise Problem(join(rule_path, "do"), f'this action does not work with "{trigger}" on this control')
            for earlier_index, earlier_rule in enumerate(rules[:rule_index]):
                if earlier_rule["control"] == control and earlier_rule["when"] == trigger:
                    raise Problem(rule_path, f"the same control and trigger as rules[{earlier_index}]")
            for earlier_index, earlier_rule in enumerate(rules[:rule_index]):
                reason = conflict(trigger, earlier_rule["when"]) if earlier_rule["control"] == control else None
                if reason:
                    raise Problem(join(rule_path, "when"),
                                  f'"{trigger}" cannot share a control with rules[{earlier_index}], because {reason}')


def check(text):
    """The config the app would load from `text`, or the Problem it would reject it with."""
    def no_constants(name):
        raise ValueError(f"{name} is not a number JSON allows")

    try:
        tree = json.loads(text, parse_constant=no_constants)
    except ValueError as error:
        raise Problem("", f"not valid JSON. {error}")
    config = decode(tree)
    unknown_key(tree, schema(tree), "")
    validate(config)
    return config


def describe(match):
    return "built-in keyboard" if match[0] == "builtIn" else f"vendor 0x{match[1]:04X}, product 0x{match[2]:04X}"


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PATH
    try:
        with open(path, encoding="utf-8") as file:
            text = file.read()
    except OSError as error:
        print(f"cannot read {path}: {error.strerror}", file=sys.stderr)
        return 2
    try:
        config = check(text)
    except Problem as problem:
        print(f"rejected: {problem}")
        return 1
    print(f"ok: {path}")
    for profile in config["devices"]:
        parts = [describe(profile["match"])]
        if profile["kind"]:
            parts.append(profile["kind"])
        parts.append(f"{len(profile['rules'])} rules")
        if profile["hyper"]:
            parts.append("hyper key")
        print(f"  {profile['name']} ({', '.join(parts)})")
    for match in config["ignored"]:
        print(f"  ignored: {describe(match)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
