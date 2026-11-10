// The seam to morphnext (KickNext, MIT, github.com/KickNext/morphnext): the
// only file in morphtext that touches its outline engine, through the public
// glyph API morphnext ships since 0.7 (MorphFont, MorphGlyph, MorphOutline,
// MorphOutlinePlan).
//
// morphnext puts a glyph's baseline at y = 0; morphtext measures y down from
// the font's ascender. Each glyph is moved down by its ascender as it's read,
// so everything past this file keeps the ascender frame.

import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:morphnext/morphnext.dart';

/// A font file, parsed once (TrueType `glyf` or CFF outlines).
final class GlyphFont {
  /// Parses [bytes] of an OpenType font file.
  GlyphFont.parse(Uint8List bytes) : this._(MorphFont.parse(bytes), null, null);

  GlyphFont._(this._font, this._weight, this._opticalSize);

  final MorphFont _font;
  final double? _weight;
  final double? _opticalSize;

  /// The design axes of a variable font, by tag (`wght`, `opsz`, ...);
  /// empty for a static one.
  Set<String> get axes => _font.axes;

  /// The same font at [weight] and [opticalSize] on its `wght` and `opsz`
  /// axes, each clamped to the axis and ignored where the font has no such
  /// axis. Null leaves an axis at its default. Shares the parsed file.
  GlyphFont varied({double? weight, double? opticalSize}) =>
      GlyphFont._(_font, weight, opticalSize);

  /// The outline of [codePoint], or null when the font lacks it or it has no
  /// contours (a space).
  GlyphShape? shape(int codePoint) {
    final outline = this.outline(codePoint);
    if (outline == null) return null;
    return GlyphShape._(outline._outline, outline.ascender);
  }

  /// The unsampled outline of [codePoint], to place with others in one
  /// shape ([GlyphShape.placed]), or null as for [shape].
  GlyphOutline? outline(int codePoint) {
    final glyph = _font.glyph(
      codePoint,
      weight: _weight,
      opticalSize: _opticalSize,
    );
    if (glyph == null) return null;
    // From the baseline to the ascender frame: x from the pen, y down from
    // the ascender.
    return GlyphOutline._(
      glyph.placed(Offset(0, glyph.ascender)),
      glyph.ascender,
    );
  }
}

/// A glyph's outline as the font draws it, in ems (x from the pen position,
/// y down from the font's ascender), not yet sampled for morphing.
final class GlyphOutline {
  GlyphOutline._(this._outline, this.ascender);

  final MorphOutline _outline;

  /// The font's ascender, in ems.
  final double ascender;
}

/// One glyph's outline in ems: x along the em from the pen position, y down
/// from the font's ascender. Or, from [GlyphShape.placed], several outlines
/// as one shape.
final class GlyphShape {
  GlyphShape._(this._outline, this.ascender);

  /// Several outlines as one shape, each scaled by its `scale` and moved to
  /// (`x`, `y`): a word's letters where its layout puts them, so the whole
  /// word morphs as one outline. Null when there's nothing to draw.
  /// [ascender] is 0: the shape is placed already.
  static GlyphShape? placed(
    Iterable<({GlyphOutline outline, double x, double y, double scale})> parts,
  ) {
    final outline = MorphOutline.combine([
      for (final p in parts)
        p.outline._outline.placed(Offset(p.x, p.y), scale: p.scale),
    ]);
    return outline == null ? null : GlyphShape._(outline, 0);
  }

  final MorphOutline _outline;

  /// The font's ascender, in ems.
  final double ascender;

  /// How many closed contours the outline has (o has two, i two, B three).
  int get contourCount => _outline.contourCount;
}

/// The morph from one glyph outline to another.
final class GlyphMorph {
  /// Pairs [from]'s contours with [to]'s (morphnext's topology-aware plan).
  GlyphMorph(GlyphShape from, GlyphShape to)
    : _plan = MorphOutlinePlan(from._outline, to._outline),
      fromAscender = from.ascender,
      toAscender = to.ascender {
    _out = _plan.allocateOutput();
  }

  final MorphOutlinePlan _plan;
  late final List<Float64List> _out;

  /// The `from` font's ascender, in ems.
  final double fromAscender;

  /// The `to` font's ascender, in ems.
  final double toAscender;

  /// The outline at [t] (0 is `from`, 1 is `to`): one closed polygon per
  /// contour pair, as interleaved x, y in ems. The buffers are reused by the
  /// next call; copy them to keep them.
  List<Float64List> at(double t) {
    _plan.interpolate(t, _out);
    return _out;
  }

  /// Whether every contour of each outline paired with exactly one of the
  /// other: nothing grew from or shrank to a point.
  bool get isOneToOne => _plan.isOneToOne;

  /// How many contour pairs the morph draws.
  int get pairCount => _plan.contourCount;
}
