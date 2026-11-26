"""Bounded, DTD-free XML reader for Breezze's build-time asset checks.

Only the limited root.tag/root.attrib/root.findall(name) contract needed by
Breezze's SVG and Android manifest validators is exposed. This does not process
external entities, DTDs, or network resources.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from xml.parsers import expat


class SafeXmlError(ValueError):
    """Malformed, potentially hostile, or oversized input."""


@dataclass
class SafeXmlNode:
    tag: str
    attrib: dict[str, str]
    children: list["SafeXmlNode"] = field(default_factory=list)

    def findall(self, name: str) -> list["SafeXmlNode"]:
        return [child for child in self.children if child.tag == name]


def parse_xml_bytes(payload: bytes, *, max_bytes: int = 16 * 1024 * 1024) -> SafeXmlNode:
    if not isinstance(payload, bytes) or len(payload) > max_bytes or not payload:
        raise SafeXmlError("Invalid or oversized XML input")

    def namespace_name(name: str) -> str:
        # Match the {namespace}local spelling used by ElementTree callers.
        return "{" + name if "}" in name else name

    parser = expat.ParserCreate(namespace_separator="}")
    stack: list[SafeXmlNode] = []
    root: SafeXmlNode | None = None
    elements = 0

    def reject(*_args: object) -> None:
        raise SafeXmlError("DOCTYPE and entities are forbidden")

    def start(name: str, attrs: dict[str, str]) -> None:
        nonlocal root, elements
        elements += 1
        if len(stack) >= 128 or elements > 100_000:
            raise SafeXmlError("XML nesting or element budget exceeded")
        node = SafeXmlNode(
            tag=namespace_name(name),
            attrib={namespace_name(k): v for k, v in attrs.items()},
        )
        if stack:
            stack[-1].children.append(node)
        else:
            if root is not None:
                raise SafeXmlError("Multiple XML root elements")
            root = node
        stack.append(node)

    def end(_name: str) -> None:
        stack.pop()

    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.StartDoctypeDeclHandler = reject
    parser.EntityDeclHandler = reject
    parser.ExternalEntityRefHandler = lambda *_args: (reject(), 0)[1]
    parser.SetParamEntityParsing(expat.XML_PARAM_ENTITY_PARSING_NEVER)
    try:
        parser.Parse(payload, True)
    except expat.ExpatError as exc:
        raise SafeXmlError("Invalid XML syntax") from exc
    if root is None or stack:
        raise SafeXmlError("Incomplete XML document")
    return root
