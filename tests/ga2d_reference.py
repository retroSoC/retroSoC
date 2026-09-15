"""Independent byte-accurate reference helpers for GA2D P5 operations."""

from __future__ import annotations

from dataclasses import dataclass


RGB565 = 0
RGB888 = 1
XRGB8888 = 2
ARGB8888 = 3
A8 = 4

FILL = 0
COPY = 1
CONVERT = 2
BLEND = 3

COLOR_FORMATS = (RGB565, RGB888, XRGB8888, ARGB8888)
FOREGROUND_FORMATS = (*COLOR_FORMATS, A8)

BYTES_PER_PIXEL = {
    RGB565: 2,
    RGB888: 3,
    XRGB8888: 4,
    ARGB8888: 4,
    A8: 1,
}

PIXEL_ALIGNMENT = {
    RGB565: 2,
    RGB888: 1,
    XRGB8888: 4,
    ARGB8888: 4,
    A8: 1,
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
        raise ValueError(f"unsupported P5 format {fmt}") from error


def pixel_alignment(fmt: int) -> int:
    try:
        return PIXEL_ALIGNMENT[fmt]
    except KeyError as error:
        raise ValueError(f"unsupported P5 format {fmt}") from error


def is_color_format(fmt: int) -> bool:
    return fmt in COLOR_FORMATS


def row_bytes(width: int, fmt: int) -> int:
    if not 1 <= width <= 0xFFFF:
        raise ValueError("width is outside the P5 range")
    return width * bytes_per_pixel(fmt)


def extent(plane: Plane, width: int, height: int) -> tuple[int, int]:
    if not 1 <= height <= 0xFFFF:
        raise ValueError("height is outside the P5 range")
    alignment = pixel_alignment(plane.fmt)
    if plane.base < 0 or plane.base > 0xFFFFFFFF:
        raise ValueError("base is outside the 32-bit P5 address space")
    if plane.base % alignment != 0 or plane.pitch % alignment != 0:
        raise ValueError("plane is not naturally pixel aligned")
    bytes_per_row = row_bytes(width, plane.fmt)
    if plane.pitch < bytes_per_row:
        raise ValueError("pitch is shorter than a logical row")
    end = plane.base + (height - 1) * plane.pitch + bytes_per_row
    if end > (1 << 32):
        raise ValueError("plane extent overflows the P5 address space")
    return plane.base, end


def ranges_overlap(left: tuple[int, int], right: tuple[int, int]) -> bool:
    return left[0] < right[1] and right[0] < left[1]


def _require_color_format(fmt: int, role: str) -> None:
    if not is_color_format(fmt):
        raise ValueError(f"{role} requires a color format")


def _rgba_from_color(color: int) -> tuple[int, int, int, int]:
    if not 0 <= color <= 0xFFFFFFFF:
        raise ValueError("COLOR must be an unsigned 32-bit value")
    return (
        (color >> 16) & 0xFF,
        (color >> 8) & 0xFF,
        color & 0xFF,
        (color >> 24) & 0xFF,
    )


def pack_rgba(red: int, green: int, blue: int, alpha: int, fmt: int) -> bytes:
    """Pack canonical RGBA channels in the frozen P5 memory byte order."""

    _require_color_format(fmt, "destination")
    if not all(0 <= channel <= 0xFF for channel in (red, green, blue, alpha)):
        raise ValueError("RGBA channels must be unsigned bytes")
    if fmt == RGB565:
        packed = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
        return packed.to_bytes(2, byteorder="little")
    if fmt == RGB888:
        return bytes((red, green, blue))
    if fmt == XRGB8888:
        return bytes((blue, green, red, 0xFF))
    return bytes((blue, green, red, alpha))


def unpack_pixel(pixel: bytes, fmt: int) -> tuple[int, int, int, int]:
    """Decode one color pixel; A8 is intentionally handled as coverage separately."""

    _require_color_format(fmt, "source")
    expected_bytes = bytes_per_pixel(fmt)
    if len(pixel) != expected_bytes:
        raise ValueError("pixel byte count does not match format")
    if fmt == RGB565:
        packed = int.from_bytes(pixel, byteorder="little")
        red5 = (packed >> 11) & 0x1F
        green6 = (packed >> 5) & 0x3F
        blue5 = packed & 0x1F
        return (
            (red5 << 3) | (red5 >> 2),
            (green6 << 2) | (green6 >> 4),
            (blue5 << 3) | (blue5 >> 2),
            0xFF,
        )
    if fmt == RGB888:
        return (pixel[0], pixel[1], pixel[2], 0xFF)
    if fmt == XRGB8888:
        return (pixel[2], pixel[1], pixel[0], 0xFF)
    return (pixel[2], pixel[1], pixel[0], pixel[3])


def pack_color(color: int, fmt: int) -> bytes:
    """Return FILL's frozen memory bytes for COLOR=0xAARRGGBB."""

    return pack_rgba(*_rgba_from_color(color), fmt)


def convert_pixel(pixel: bytes, source_format: int, destination_format: int) -> bytes:
    """Convert one color pixel with the P5 X/ARGB alpha rules."""

    _require_color_format(source_format, "foreground")
    _require_color_format(destination_format, "destination")
    red, green, blue, alpha = unpack_pixel(pixel, source_format)
    converted_alpha = alpha if source_format == ARGB8888 and destination_format == ARGB8888 else 0xFF
    return pack_rgba(red, green, blue, converted_alpha, destination_format)


def effective_alpha(plane_alpha: int, global_alpha: int) -> int:
    if not 0 <= plane_alpha <= 0xFF or not 0 <= global_alpha <= 0xFF:
        raise ValueError("alpha inputs must be unsigned bytes")
    return (plane_alpha * global_alpha + 127) // 255


def blend_channel(foreground: int, background: int, alpha: int) -> int:
    if not all(0 <= channel <= 0xFF for channel in (foreground, background, alpha)):
        raise ValueError("blend inputs must be unsigned bytes")
    return (foreground * alpha + background * (255 - alpha) + 127) // 255


def blend_pixel(
    foreground: bytes,
    foreground_format: int,
    background: bytes,
    background_format: int,
    destination_format: int,
    global_alpha: int,
    color: int,
) -> bytes:
    """Blend a foreground color/A8 coverage over opaque background RGB."""

    _require_color_format(background_format, "background")
    _require_color_format(destination_format, "destination")
    if foreground_format == A8:
        if len(foreground) != 1:
            raise ValueError("A8 foreground requires one byte")
        foreground_red, foreground_green, foreground_blue, _ = _rgba_from_color(color)
        source_alpha = foreground[0]
    else:
        _require_color_format(foreground_format, "foreground")
        foreground_red, foreground_green, foreground_blue, source_alpha = unpack_pixel(
            foreground, foreground_format
        )
    background_red, background_green, background_blue, _ = unpack_pixel(
        background, background_format
    )
    alpha = effective_alpha(source_alpha, global_alpha)
    return pack_rgba(
        blend_channel(foreground_red, background_red, alpha),
        blend_channel(foreground_green, background_green, alpha),
        blend_channel(foreground_blue, background_blue, alpha),
        0xFF,
        destination_format,
    )


def _check_destination_foreground_overlap(
    foreground: Plane, destination: Plane, width: int, height: int
) -> None:
    if ranges_overlap(extent(foreground, width, height), extent(destination, width, height)):
        raise ValueError("P5 rejects all foreground/destination overlap")


def _background_destination_is_exactly_inplace(background: Plane, destination: Plane) -> bool:
    return (
        background.base == destination.base
        and background.pitch == destination.pitch
        and background.fmt == destination.fmt
    )


def _check_background_destination_overlap(
    background: Plane, destination: Plane, width: int, height: int
) -> None:
    if ranges_overlap(extent(background, width, height), extent(destination, width, height)) and (
        not _background_destination_is_exactly_inplace(background, destination)
    ):
        raise ValueError("P5 permits background/destination overlap only when exactly in-place")


def _pixel_address(plane: Plane, line: int, pixel: int) -> int:
    return plane.base + line * plane.pitch + pixel * bytes_per_pixel(plane.fmt)


def fill(memory: bytearray, plane: Plane, width: int, height: int, color: int) -> None:
    _require_color_format(plane.fmt, "destination")
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
    _require_color_format(foreground.fmt, "foreground")
    _require_color_format(destination.fmt, "destination")
    if foreground.fmt != destination.fmt:
        raise ValueError("P5 COPY requires matching foreground and destination formats")
    _check_destination_foreground_overlap(foreground, destination, width, height)
    bytes_per_row = row_bytes(width, foreground.fmt)
    for line in range(height):
        source = foreground.base + line * foreground.pitch
        target = destination.base + line * destination.pitch
        memory[target : target + bytes_per_row] = memory[source : source + bytes_per_row]


def convert(
    memory: bytearray,
    foreground: Plane,
    destination: Plane,
    width: int,
    height: int,
) -> None:
    _require_color_format(foreground.fmt, "foreground")
    _require_color_format(destination.fmt, "destination")
    _check_destination_foreground_overlap(foreground, destination, width, height)
    for line in range(height):
        for pixel in range(width):
            source_address = _pixel_address(foreground, line, pixel)
            destination_address = _pixel_address(destination, line, pixel)
            source = memory[source_address : source_address + bytes_per_pixel(foreground.fmt)]
            memory[destination_address : destination_address + bytes_per_pixel(destination.fmt)] = (
                convert_pixel(source, foreground.fmt, destination.fmt)
            )


def blend(
    memory: bytearray,
    foreground: Plane,
    background: Plane,
    destination: Plane,
    width: int,
    height: int,
    global_alpha: int,
    color: int,
) -> None:
    if foreground.fmt not in FOREGROUND_FORMATS:
        raise ValueError("foreground has an unsupported P5 format")
    _require_color_format(background.fmt, "background")
    _require_color_format(destination.fmt, "destination")
    _check_destination_foreground_overlap(foreground, destination, width, height)
    _check_background_destination_overlap(background, destination, width, height)
    for line in range(height):
        for pixel in range(width):
            foreground_address = _pixel_address(foreground, line, pixel)
            background_address = _pixel_address(background, line, pixel)
            destination_address = _pixel_address(destination, line, pixel)
            foreground_pixel = memory[
                foreground_address : foreground_address + bytes_per_pixel(foreground.fmt)
            ]
            background_pixel = memory[
                background_address : background_address + bytes_per_pixel(background.fmt)
            ]
            memory[destination_address : destination_address + bytes_per_pixel(destination.fmt)] = (
                blend_pixel(
                    foreground_pixel,
                    foreground.fmt,
                    background_pixel,
                    background.fmt,
                    destination.fmt,
                    global_alpha,
                    color,
                )
            )
