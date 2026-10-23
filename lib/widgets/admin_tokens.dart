import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// واجهة شاشات الإدارة إلى لوحة نون المشتركة [Noon] في `theme/app_colors.dart`
/// (مشتقة من ثيم المدرسة). أسماء مختصرة فقط — لا قيم خاصة هنا .
abstract final class AdminNoon {
  static Color get ink => Noon.ink;
  static Color get onInk => Noon.onInk;
  static Color get onInkSoft => Noon.onInkSoft;
  static Color get teal => Noon.teal;
  static Color get onTeal => Noon.onTeal;
  static Color get tealD => Noon.tealD;
  static Color get action => Noon.action;
  static Color get onAction => Noon.onAction;
  static Color get mist => Noon.mist;
  static Color get mist2 => Noon.mist2;
  static Color get band => Noon.band;
  static Color get head => Noon.head;
  static Color get headLine => Noon.headLine;
  static Color get paper => Noon.paper;
  static Color get line => Noon.line;
  static Color get rule => Noon.rule;
  static Color get ruleSoft => Noon.ruleSoft;
  static Color get muted => Noon.muted;
  static Color get faint => Noon.faint;
  static Color get text => Noon.text;

  static const sunL = Noon.sunL;
  static const warn = Noon.warn;
  static const warnD = Noon.warnD;
  static const warnLine = Noon.warnLine;
  static const green50 = Noon.green50;
  static const green200 = Noon.green200;
  static const green700 = Noon.green700;
  static const red50 = Noon.red50;
  static const red200 = Noon.red200;
  static const red600 = Noon.red600;
  static const red700 = Noon.red700;

  static const shadow = nShadow;
  static const rPanel = NoonRadius.panel;
  static const rTile = NoonRadius.tile;
  static const rTag = NoonRadius.tag;

  static Color mix(Color c, double ratio, [Color base = Colors.white]) => noonMix(c, ratio, base);
}
