"""Independent byte-accurate reference helpers for GA2D P4 FILL and COPY."""

from __future__ import annotations

from dataclasses import dataclass


RGB565 = 0
RGB888 = 1
XRGB8888 = 2
ARGB8888 = 3

BYTES_PER_PIXEL = {
    RGB565: 2,
    RGB888: 3,
    XRGB8888: 4,
    ARGB8888: 4,
}


@dataclass(frozen=True)
class Plane:
    base: int
    pitch: int
    fmt: int


def bytes_per_pixel(fmt: int) -> int:
    try:
        return BYTES_PER_PIXEL[fmt]
    except KeyError as error:
        raise ValueError(f"unsupported P4 format {fmt}") from error


def row_bytes(width: int, fmt: int) -> int:
    if not 1 <= width <= 0xFFFF:
        raise ValueError("width is outside the P4 range")
    return width * bytes_per_pixel(fmt)


def extent(plane: Plane, width: int, height: int) -> tuple[int, int]:
    if not 1 <= height <= 0xFFFF:
        raise ValueError("height is outside the P4 range")
    bpp = bytes_per_pixel(plane.fmt)
    if plane.base < 0 or plane.base > 0xFFFFFFFF:
        raise ValueError("base is outside the 32-bit P4 address space")
    if plane.base % bpp != 0 or plane.pitch % bpp != 0:
        raise ValueError("plane is not naturally pixel aligned")
    bytes_per_row = row_bytes(width, plane.fmt)
    if plane.pitch < bytes_per_row:
        raise ValueError("pitch is shorter than a logical row")
    end = plane.base + (height - 1) * plane.pitch + bytes_per_row
    if end > (1 << 32):
        raise ValueError("plane extent overflows the P4 address space")
    return plane.base, end


def ranges_overlap(left: tuple[int, int], right: tuple[int, int]) -> bool:
    return left[0] < right[1] and right[0] < left[1]


def pack_color(color: int, fmt: int) -> bytes:
    """Return the frozen P4 memory pixel bytes for COLOR=0xAARRGGBB."""

    if not 0 <= color <= 0xFFFFFFFF:
        raise ValueError("COLOR must be an unsigned 32-bit value")
    alpha = (color >> 24) & 0xFF
    red = (color >> 16) & 0xFF
    green = (color >> 8) & 0xFF
    blue = color & 0xFF
    if fmt == RGB565:
        packed = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
        return packed.to_bytes(2, byteorder="little")
    if fmt == RGB888:
        return bytes((red, green, blue))
    if fmt == XRGB8888:
        return bytes((blue, green, red, 0xFF))
    if fmt == ARGB8888:
        return bytes((blue, green, red, alpha))
    raise ValueError(f"unsupported P4 format {fmt}")


def fill(memory: bytearray, plane: Plane, width: int, height: int, color: int) -> None:
    extent(plane, width, height)
    pixel = pack_color(color, plane.fmt)
    logical_row = pixel * width
    for line in range(height):
        start = plane.base + line * plane.pitch
        memory[start : start + len(logical_row)] = logical_row


def copy(
    memory: bytearray,
    foreground: Plane,
    destination: Plane,
    width: int,
    height: int,
) -> None:
    if foreground.fmt != destination.fmt:
        raise ValueError("P4 COPY requires matching foreground and destination formats")
    if ranges_overlap(extent(foreground, width, height), extent(destination, width, height)):
        raise ValueError("P4 COPY rejects all foreground/destination overlap")
    bytes_per_row = row_bytes(width, foreground.fmt)
    for line in range(height):
        source = foreground.base + line * foreground.pitch
        target = destination.base + line * destination.pitch
        memory[target : target + bytes_per_row] = memory[source : source + bytes_per_row]
