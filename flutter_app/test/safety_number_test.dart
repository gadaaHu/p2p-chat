import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/utils/safety_number.dart';

void main() {
  final edA = Uint8List.fromList(List.generate(32, (i) => i));
  final edB = Uint8List.fromList(List.generate(32, (i) => 255 - i));

  test('symmetric', () async {
    final ab = await SafetyNumber.derive(edA, edB);
    final ba = await SafetyNumber.derive(edB, edA);
    expect(ab, ba);
  });

  test('deterministic', () async {
    final s1 = await SafetyNumber.derive(edA, edB);
    final s2 = await SafetyNumber.derive(edA, edB);
    expect(s1, s2);
  });

  test('60 digits, all decimal', () async {
    final s = await SafetyNumber.derive(edA, edB);
    expect(s.length, SafetyNumber.totalDigits);
    expect(RegExp(r'^\d{60}$').hasMatch(s), isTrue);
  });

  test('changing one byte of one key changes the number', () async {
    final s1 = await SafetyNumber.derive(edA, edB);
    final edB2 = Uint8List.fromList(edB);
    edB2[0] ^= 0x01;
    final s2 = await SafetyNumber.derive(edA, edB2);
    expect(s1, isNot(s2));
  });

  test('unrelated keys do not collide on prefix', () async {
    final s1 = await SafetyNumber.derive(edA, edB);
    final edC = Uint8List.fromList(List.filled(32, 42));
    final s2 = await SafetyNumber.derive(edA, edC);
    expect(s1.substring(0, 20), isNot(s2.substring(0, 20)));
  });

  test('format inserts spaces every 5 digits', () {
    final raw = '1234567890' * 6;
    final formatted = SafetyNumber.format(raw);
    expect(formatted.split(' ').length, SafetyNumber.groups);
    expect(formatted.replaceAll(' ', '').length, 60);
  });

  test('chunk splits into 12 groups of 5', () {
    final raw = '1234567890' * 6;
    final chunks = SafetyNumber.chunk(raw);
    expect(chunks.length, SafetyNumber.groups);
    expect(chunks.every((c) => c.length == 5), isTrue);
    expect(chunks.join(), raw);
  });
}