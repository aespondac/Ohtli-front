import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/photo_storage.dart';
import 'package:othli_front/widgets/image_cropper_dialog.dart';

void main() {
  const image = Size(4000, 3000); // foto horizontal
  const viewport = Size(300, 400); // encuadre 3:4

  test('coverSize cubre el encuadre sin deformar', () {
    final c = coverSize(image, viewport);
    expect(c.height, closeTo(400, 1e-9));
    expect(c.width, closeTo(533.33, 0.01));
  });

  test('sin zoom y centrada, recorta el centro a lo alto', () {
    final content = coverSize(image, viewport);
    final m = Matrix4.translationValues(-(content.width - viewport.width) / 2, 0, 0);
    final r = cropSourceRect(m: m, viewport: viewport, content: content, image: image);
    expect(r.height, closeTo(3000, 0.01));
    expect(r.width, closeTo(2250, 0.01)); // 3:4
    expect(r.center.dx, closeTo(2000, 0.01));
  });

  test('arrastrada a la izquierda del todo, recorta el borde izquierdo', () {
    final content = coverSize(image, viewport);
    final r = cropSourceRect(m: Matrix4.identity(), viewport: viewport, content: content, image: image);
    expect(r.left, closeTo(0, 1e-9));
    expect(r.width, closeTo(2250, 0.01));
  });

  test('el zoom con la barra acerca alrededor del centro y no deja huecos', () {
    final content = coverSize(image, viewport);
    final centered = Matrix4.translationValues(-(content.width - viewport.width) / 2, 0, 0);
    final z2 = zoomAroundCenter(centered, 2, viewport, content);
    final r = cropSourceRect(m: z2, viewport: viewport, content: content, image: image);
    expect(r.width, closeTo(1125, 0.01));
    expect(r.center.dx, closeTo(2000, 0.5));
    expect(r.center.dy, closeTo(1500, 0.5));
    // Desde una esquina, el zoom no se sale de la imagen
    final corner = zoomAroundCenter(Matrix4.identity(), 3, viewport, content);
    final rc = cropSourceRect(m: corner, viewport: viewport, content: content, image: image);
    expect(rc.left, greaterThanOrEqualTo(0));
    expect(rc.top, greaterThanOrEqualTo(0));
  });

  test('bytesOf acepta data URI o base64 solo', () {
    final b64 = base64Encode([1, 2, 3]);
    expect(PhotoStorage.bytesOf('data:image/jpeg;base64,$b64'), [1, 2, 3]);
    expect(PhotoStorage.bytesOf(b64), [1, 2, 3]);
  });
}
