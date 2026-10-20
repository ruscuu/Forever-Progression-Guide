"""Lectura y escritura de tablas Lua literales.

- parse_assignments(): lee un archivo de SavedVariables (`Nombre = { ... }`).
- to_lua(): serializa datos de Python a un literal Lua determinista, para que
  el diff de los archivos generados solo muestre cambios reales.
"""

import re

_TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<comment>--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
  | (?P<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
  | (?P<number>-?0[xX][0-9a-fA-F]+|-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[{}\[\]=,;])
""", re.VERBOSE | re.DOTALL)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}


class LuaParseError(ValueError):
    pass


def _unescape(body):
    out, i = [], 0
    raw = bytearray()

    def flush():
        if raw:
            out.append(raw.decode("utf-8", errors="replace"))
            raw.clear()

    while i < len(body):
        ch = body[i]
        if ch != "\\":
            flush()
            out.append(ch)
            i += 1
            continue
        nxt = body[i + 1]
        if nxt.isdigit():
            # \ddd son bytes; WoW escribe así los caracteres UTF-8 en algunos casos.
            digits = re.match(r"\d{1,3}", body[i + 1:]).group()
            raw.append(int(digits))
            i += 1 + len(digits)
        else:
            flush()
            out.append(_ESCAPES.get(nxt, nxt))
            i += 2
    flush()
    return "".join(out)


def _tokenize(text):
    pos = 0
    tokens = []
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise LuaParseError(f"carácter inesperado en la posición {pos}: {text[pos:pos + 20]!r}")
        pos = m.end()
        kind = m.lastgroup if m.lastgroup != "eq" else "comment"
        if kind in ("ws", "comment"):
            continue
        tokens.append((kind, m.group(kind)))
    return tokens


class _Parser:
    def __init__(self, text):
        self.tokens = _tokenize(text)
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else (None, None)

    def take(self, value=None):
        tok = self.peek()
        if tok[0] is None or (value is not None and tok[1] != value):
            raise LuaParseError(f"se esperaba {value!r} y llegó {tok[1]!r}")
        self.i += 1
        return tok

    def value(self):
        kind, text = self.take()
        if kind == "string":
            return _unescape(text[1:-1])
        if kind == "number":
            return int(text, 16) if "x" in text.lower() else (float(text) if re.search(r"[.eE]", text) else int(text))
        if kind == "name":
            if text in ("true", "false"):
                return text == "true"
            if text == "nil":
                return None
            raise LuaParseError(f"identificador inesperado: {text}")
        if text == "{":
            return self.table()
        raise LuaParseError(f"valor inesperado: {text!r}")

    def table(self):
        result, n = {}, 0
        while self.peek()[1] != "}":
            kind, text = self.peek()
            if text == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                result[key] = self.value()
            elif kind == "name" and self.tokens[self.i + 1][1] == "=":
                self.i += 2
                result[text] = self.value()
            else:
                n += 1
                result[n] = self.value()
            if self.peek()[1] in (",", ";"):
                self.i += 1
        self.take("}")
        return _as_list_if_sequence(result)


def _as_list_if_sequence(table):
    if table and all(isinstance(k, int) and not isinstance(k, bool) for k in table) and sorted(table) == list(range(1, len(table) + 1)):
        return [table[k] for k in range(1, len(table) + 1)]
    return table


def parse_assignments(text):
    """Devuelve {nombre: valor} para un archivo de SavedVariables."""
    parser = _Parser(text)
    result = {}
    while parser.peek()[0] is not None:
        kind, name = parser.take()
        if kind != "name":
            raise LuaParseError(f"se esperaba un nombre de variable y llegó {name!r}")
        parser.take("=")
        result[name] = parser.value()
    return result


_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_LUA_KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
                 "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}


def _lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'


def _lua_key(k):
    if isinstance(k, str) and _IDENT.match(k) and k not in _LUA_KEYWORDS:
        return k
    if isinstance(k, str):
        return f"[{_lua_string(k)}]"
    return f"[{k}]"


def to_lua(value, indent=0, compact=False):
    """Literal Lua determinista. Con compact=True, todo en una línea."""
    if compact:
        return _to_lua_compact(value)
    pad = "  " * indent
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return _lua_string(value)
    if isinstance(value, (list, tuple)):
        if not value:
            return "{}"
        if all(not isinstance(v, (dict, list, tuple)) for v in value):
            return "{ " + ", ".join(to_lua(v) for v in value) + " }"
        items = [f"{pad}  {to_lua(v, indent + 1)}," for v in value]
        return "{\n" + "\n".join(items) + f"\n{pad}}}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        keys = sorted(value, key=lambda k: (not isinstance(k, (int, float)), k if isinstance(k, (int, float)) else str(k)))
        keys = [k for k in keys if value[k] is not None]
        if len(keys) <= 4 and all(not isinstance(value[k], (dict, list, tuple)) for k in keys):
            return "{ " + ", ".join(f"{_lua_key(k)} = {to_lua(value[k])}" for k in keys) + " }"
        items = [f"{pad}  {_lua_key(k)} = {to_lua(value[k], indent + 1)}," for k in keys]
        return "{\n" + "\n".join(items) + f"\n{pad}}}"
    raise TypeError(f"tipo no serializable a Lua: {type(value).__name__}")


def _to_lua_compact(value):
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(_to_lua_compact(v) for v in value) + "}"
    if isinstance(value, dict):
        keys = sorted((k for k in value if value[k] is not None),
                      key=lambda k: (not isinstance(k, (int, float)), k if isinstance(k, (int, float)) else str(k)))
        return "{" + ",".join(f"{_lua_key(k)}={_to_lua_compact(value[k])}" for k in keys) + "}"
    return to_lua(value)
