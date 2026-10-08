import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../models/pour_model.dart';

class PourController extends GetxController
    with GetSingleTickerProviderStateMixin {
  static const _asset = 'assets/images/plant.png';
  static const _jugAsset = 'assets/images/watering_jug.png';
  static const _roseU = 0.836;
  static const _roseV = 0.070;
  static const _nozzleU = 0.838;
  static const _nozzleV = 0.090;
  static const _pivotU = 0.467;
  static const _pivotV = 0.512;
  static const _minTilt = -0.18;
  static const _maxTilt = 2.05;
  static const _pourDy = 0.16;
  static const _cols = 32;
  static const _rows = 40;
  static const _alphaW = 96;
  static const _alphaH = 96;

  final ValueNotifier<int> frame = ValueNotifier<int>(0);
  late final Ticker _ticker;
  final math.Random _random = math.Random();

  final List<Frond> _fronds = [
    Frond(
      centerU: 0.28,
      pivotU: 0.47,
      pivotV: 0.72,
      sigma: 0.13,
      phase: 0.4,
      speed: 1.15,
    ),
    Frond(
      centerU: 0.39,
      pivotU: 0.49,
      pivotV: 0.70,
      sigma: 0.12,
      phase: 1.7,
      speed: 1.35,
    ),
    Frond(
      centerU: 0.50,
      pivotU: 0.50,
      pivotV: 0.64,
      sigma: 0.12,
      phase: 2.4,
      speed: 1.05,
    ),
    Frond(
      centerU: 0.62,
      pivotU: 0.51,
      pivotV: 0.70,
      sigma: 0.12,
      phase: 0.9,
      speed: 1.28,
    ),
    Frond(
      centerU: 0.76,
      pivotU: 0.54,
      pivotV: 0.72,
      sigma: 0.13,
      phase: 2.1,
      speed: 1.18,
    ),
  ];

  final List<Drop> _drops = [];
  final List<Spark> _sparks = [];
  final List<Bead> _beads = [];
  final List<Ring> _rings = [];
  final List<Mote> _motes = [];

  ui.Image? _image;
  ui.Image? _jug;
  ui.ImageShader? _shader;
  Uint8List? _alpha;
  Float32List? _positions;
  Float32List? _uvs;
  Uint16List? _indices;

  Size? screenSize;
  Duration _lastElapsed = Duration.zero;
  double _time = 0;
  double _spawnDebt = 0;
  double _jugAngle = 0;
  double _jugVel = 0;
  bool _dragging = false;
  bool _wasPouring = false;
  Offset? _lastPointer;
  final showHint = true.obs;
  final errorMessage = RxnString();
  final ready = false.obs;
  double _growth = 0;
  double _shownGrowth = 0;
  double _jugWater = 0.88;
  double _soilWet = 0;
  double _pulse = 0;
  double _fullBreath = 0;
  int _reached = 0;
  final whisperBand = 0.obs;
  bool reduceMotion = false;

  @override
  void onInit() {
    super.onInit();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    _ticker = createTicker(_onTick)..start();
    _loadPlant();
  }

  @override
  void onClose() {
    _ticker.dispose();
    frame.dispose();
    _image?.dispose();
    _jug?.dispose();
    super.onClose();
  }

  Future<void> _loadPlant() async {
    try {
      final data = await rootBundle.load(_asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (isClosed) {
        image.dispose();
        return;
      }
      if (bytes == null) {
        image.dispose();
        errorMessage.value = 'Could not read the plant render';
        return;
      }
      _buildAlpha(image, bytes);
      _buildMesh(image);
      _shader = ui.ImageShader(
        image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        Float64List.fromList(Matrix4.identity().storage),
        filterQuality: ui.FilterQuality.medium,
      );
      final jugData = await rootBundle.load(_jugAsset);
      final jugCodec = await ui.instantiateImageCodec(
        jugData.buffer.asUint8List(),
      );
      final jugFrame = await jugCodec.getNextFrame();
      if (isClosed) {
        image.dispose();
        jugFrame.image.dispose();
        return;
      }
      _image = image;
      _jug = jugFrame.image;
      ready.value = true;
    } catch (_) {
      if (isClosed) return;
      errorMessage.value = 'Could not load the plant render';
    }
  }

  void _buildAlpha(ui.Image image, ByteData bytes) {
    final rgba = bytes.buffer.asUint8List();
    final alpha = Uint8List(_alphaW * _alphaH);
    final iw = image.width;
    final ih = image.height;
    for (var gy = 0; gy < _alphaH; gy++) {
      final sy = ((gy + 0.5) / _alphaH * ih).floor().clamp(0, ih - 1);
      for (var gx = 0; gx < _alphaW; gx++) {
        final sx = ((gx + 0.5) / _alphaW * iw).floor().clamp(0, iw - 1);
        alpha[gy * _alphaW + gx] = rgba[(sy * iw + sx) * 4 + 3];
      }
    }
    _alpha = alpha;
  }

  void _buildMesh(ui.Image image) {
    final vertexCount = (_cols + 1) * (_rows + 1);
    final positions = Float32List(vertexCount * 2);
    final uvs = Float32List(vertexCount * 2);
    for (var r = 0; r <= _rows; r++) {
      for (var c = 0; c <= _cols; c++) {
        final i = (r * (_cols + 1) + c) * 2;
        uvs[i] = c / _cols * image.width;
        uvs[i + 1] = r / _rows * image.height;
      }
    }
    final indices = Uint16List(_cols * _rows * 6);
    var k = 0;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final i = r * (_cols + 1) + c;
        indices[k++] = i;
        indices[k++] = i + 1;
        indices[k++] = i + _cols + 1;
        indices[k++] = i + 1;
        indices[k++] = i + _cols + 2;
        indices[k++] = i + _cols + 1;
      }
    }
    _positions = positions;
    _uvs = uvs;
    _indices = indices;
  }

  void _onTick(Duration elapsed) {
    final size = screenSize;
    if (_image == null || size == null || size.isEmpty) {
      _lastElapsed = elapsed;
      return;
    }
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;
    _step(dt, size);
    frame.value++;
  }

  void _step(double dt, Size size) {
    _time += dt;
    final plant = _plantRect(size);
    _stepJug(dt);
    _shownGrowth += (_growth - _shownGrowth) * (1 - math.exp(-1.6 * dt));
    _pulse *= math.exp(-1.7 * dt);
    _soilWet = math.max(0, _soilWet - dt * 0.018);
    final dir = _spoutDirection();
    final pouring = dir.dy > _pourDy && _jugWater > 0.08;
    if (pouring && !_wasPouring) HapticFeedback.lightImpact();
    _wasPouring = pouring;
    if (pouring) {
      final power = _pourPower(dir.dy);
      _jugWater = math.max(0.06, _jugWater - dt * (0.035 + power * 0.06));
    } else {
      _jugWater = math.min(0.9, _jugWater + dt * 0.03);
    }

    for (final frond in _fronds) {
      final breeze =
          math.sin(_time * frond.speed * 0.55 + frond.phase) * 0.05 +
          math.sin(_time * frond.speed * 0.23 + frond.phase * 1.7) * 0.022;
      frond.lean *= math.exp(-0.7 * dt);
      final target = (frond.lean + breeze).clamp(-0.22, 0.22);
      const stiffness = 10.0;
      const damping = 7.4;
      final acc = stiffness * (target - frond.angle) - damping * frond.vel;
      frond.vel += acc * dt;
      frond.angle += frond.vel * dt;
    }

    _spawnDebt += dt;
    if (pouring) {
      final power = _pourPower(dir.dy);
      final interval = 0.03 - power * 0.012;
      while (_spawnDebt >= interval && _drops.length < 200) {
        _spawnDebt -= interval;
        _spawnShower(size, plant, dir, power);
        if (power > 0.35 && _drops.length < 200) {
          _spawnShower(size, plant, dir, power);
        }
      }
    } else if (_spawnDebt > 0.2) {
      _spawnDebt = 0;
    }

    for (var i = _drops.length - 1; i >= 0; i--) {
      final drop = _drops[i];
      drop.vy += 1100 * dt;
      drop.vx *= math.exp(-0.45 * dt);
      drop.x += drop.vx * dt;
      drop.y += drop.vy * dt;

      if (drop.y > size.height - 6) {
        _strikeFloor(drop);
        _drops.removeAt(i);
        continue;
      }

      final hit = _hitPlant(drop.x, drop.y, plant);
      if (hit == null) continue;
      if (hit.$2 < 0.745) {
        _strikeLeaf(hit.$1, hit.$2, drop);
        final fallsThrough = hit.$2 < 0.6 && _random.nextDouble() < 0.42;
        if (fallsThrough) {
          drop.y += 8;
          drop.vy *= 0.55;
          drop.size *= 0.82;
          continue;
        }
      } else {
        _strikePot(drop);
      }
      _drops.removeAt(i);
    }

    for (var i = _sparks.length - 1; i >= 0; i--) {
      final spark = _sparks[i];
      spark.vy += 980 * dt;
      spark.x += spark.vx * dt;
      spark.y += spark.vy * dt;
      spark.life -= dt * 1.8;
      if (spark.life <= 0) _sparks.removeAt(i);
    }

    for (var i = _beads.length - 1; i >= 0; i--) {
      final bead = _beads[i];
      if (bead.u != null && bead.v != null) {
        if (!reduceMotion) bead.v = bead.v! + dt * 0.012;
        final stuck = _grownPoint(bead.u!, bead.v!, plant);
        bead.x = stuck.dx;
        bead.y = stuck.dy;
        bead.life -= dt * 0.012;
        if (bead.v! >= 0.70) {
          bead.u = null;
          bead.v = null;
          bead.vy = 22;
          bead.life = math.min(bead.life, 0.7);
        }
      } else if (bead.onLedge) {
        bead.life -= dt * 0.01;
      } else {
        bead.vy += 36 * dt;
        bead.vx *= math.exp(-2.4 * dt);
        bead.x += bead.vx * dt;
        bead.y += bead.vy * dt;
        final onLeaf = _hitPlant(bead.x, bead.y, plant);
        if (onLeaf != null && onLeaf.$2 < 0.7 && bead.vy < 48) {
          bead.u = onLeaf.$1;
          bead.v = onLeaf.$2;
          bead.vx = 0;
          bead.vy = 0;
        } else if (bead.y >= _ledgeY(plant)) {
          bead.y = _ledgeY(plant);
          bead.onLedge = true;
          bead.vx = 0;
          bead.vy = 0;
        }
        bead.life -= dt * 0.12;
      }
      if (bead.life <= 0) _beads.removeAt(i);
    }

    for (var i = _rings.length - 1; i >= 0; i--) {
      final ring = _rings[i];
      ring.life -= dt * (ring.warm ? 0.85 : 1.7);
      if (ring.life <= 0) _rings.removeAt(i);
    }

    for (var i = _motes.length - 1; i >= 0; i--) {
      final mote = _motes[i];
      mote.vy -= 14 * dt;
      mote.vx *= math.exp(-0.7 * dt);
      mote.x += (mote.vx + math.sin(_time * 2.2 + mote.phase) * 10) * dt;
      mote.y += mote.vy * dt;
      mote.life -= dt * 0.32;
      if (mote.life <= 0 || mote.y < -20) _motes.removeAt(i);
    }

    if (_growth >= 1 && !reduceMotion) {
      _fullBreath += dt;
      if (_fullBreath > 3.4) {
        _fullBreath = 0;
        final crown = _grownPoint(0.5, 0.30, plant);
        _riseMotes(crown.dx, crown.dy, 2, gold: true);
      }
    } else {
      _fullBreath = 0;
    }
    _syncWhisper();
  }

  (double, double)? _hitPlant(double x, double y, Rect plant) {
    final alpha = _alpha;
    final uv = _screenToPlantUv(x, y, plant);
    if (alpha == null || uv == null) return null;
    final gx = (uv.$1 * (_alphaW - 1)).round().clamp(0, _alphaW - 1);
    final gy = (uv.$2 * (_alphaH - 1)).round().clamp(0, _alphaH - 1);
    if (alpha[gy * _alphaW + gx] < 28) return null;
    return uv;
  }

  (double, double)? _screenToPlantUv(double x, double y, Rect plant) {
    final nx = (x - plant.left) / plant.width;
    final ny = (y - plant.top) / plant.height;
    final crown = _mappedV(0);
    if (ny < crown - 0.02 || ny > 1.02 || nx < -0.05 || nx > 1.05) {
      return null;
    }
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 16; i++) {
      final mid = (lo + hi) / 2;
      if (_mappedV(mid) < ny) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final v = (lo + hi) / 2;
    final scale = _partScale(v);
    if (scale < 0.05) return null;
    final u = 0.5 + (nx - 0.5) / scale;
    if (u < 0 || u > 1 || v < 0 || v > 1) return null;
    return (u, v);
  }

  double get _foliageGrowth => 0.42 + 0.58 * _shownGrowth;

  double _partScale(double v) {
    const rim = 0.70;
    const crown = 0.56;
    final growth = _foliageGrowth;
    if (v >= rim) return 1;
    if (v <= crown) return growth;
    final t = (rim - v) / (rim - crown);
    return 1 + (growth - 1) * t;
  }

  double _mappedV(double v) {
    const rim = 0.70;
    return rim + (v - rim) * _partScale(v);
  }

  Offset _growthAnchor(Rect plant) {
    return Offset(plant.center.dx, plant.top + plant.height * 0.70);
  }

  Offset _grownPoint(double u, double v, Rect plant) {
    final scale = _partScale(v);
    final anchor = _growthAnchor(plant);
    final x = plant.left + u * plant.width;
    final y = plant.top + v * plant.height;
    return Offset(
      anchor.dx + (x - anchor.dx) * scale,
      anchor.dy + (y - anchor.dy) * scale,
    );
  }

  double _ledgeY(Rect plant) => plant.top + plant.height * 0.935;

  void _leaveDew(
    double x,
    double y,
    double size, {
    double? u,
    double? v,
    bool onLedge = false,
  }) {
    if (_beads.length >= 52) {
      final moving = _beads.indexWhere(
        (bead) => bead.u == null && !bead.onLedge,
      );
      if (moving >= 0) {
        _beads.removeAt(moving);
      } else if (_beads.isNotEmpty) {
        _beads.removeAt(0);
      }
    }
    _beads.add(
      Bead(
        x: x,
        y: y,
        vx: 0,
        vy: 0,
        life: 1,
        size: size,
        glint: _random.nextDouble() * math.pi * 2,
        u: u,
        v: v,
        onLedge: onLedge,
      ),
    );
  }

  void _strikeLeaf(double u, double v, Drop drop) {
    final depth = ((v - 0.22) / 0.5).clamp(0.35, 1.0);
    for (final frond in _fronds) {
      final weight = math.exp(-math.pow((u - frond.centerU) / 0.13, 2));
      if (weight < 0.08) continue;
      final sign = (frond.centerU - 0.5).abs() < 0.04
          ? (u < 0.5 ? -1.0 : 1.0)
          : (frond.centerU < 0.5 ? -1.0 : 1.0);
      final push = sign * (0.055 + depth * 0.04) * weight;
      frond.lean = (frond.lean + push).clamp(-0.2, 0.2);
    }
    _absorb(0.005, drop.x, drop.y);

    if (_sparks.length < 220) {
      final count = 4 + _random.nextInt(3);
      for (var s = 0; s < count; s++) {
        final ang = -math.pi * (0.15 + _random.nextDouble() * 0.7);
        final speed = 40 + _random.nextDouble() * 110;
        _sparks.add(
          Spark(
            x: drop.x,
            y: drop.y,
            vx: math.cos(ang) * speed * (_random.nextBool() ? 1 : -1),
            vy: math.sin(ang) * speed,
            life: 0.7 + _random.nextDouble() * 0.4,
            size: drop.size * (0.28 + _random.nextDouble() * 0.35),
          ),
        );
      }
    }

    if (_random.nextDouble() < 0.72) {
      _leaveDew(drop.x, drop.y, drop.size * 0.9, u: u, v: v);
    } else if (_beads.length < 52) {
      _beads.add(
        Bead(
          x: drop.x,
          y: drop.y,
          vx: (0.5 - u) * 10,
          vy: 12 + _random.nextDouble() * 16,
          life: 1,
          size: drop.size * 0.7,
          glint: _random.nextDouble() * math.pi * 2,
        ),
      );
    }

    if (_rings.length < 10 && _random.nextDouble() > 0.55) {
      _rings.add(Ring(x: drop.x, y: drop.y, maxR: drop.size * 2.2));
    }
  }

  void _strikeFloor(Drop drop) {
    final plant = screenSize == null ? null : _plantRect(screenSize!);
    if (plant != null &&
        drop.x > plant.left + plant.width * 0.18 &&
        drop.x < plant.right - plant.width * 0.18 &&
        _random.nextDouble() < 0.55) {
      _leaveDew(drop.x, _ledgeY(plant), drop.size * 0.75, onLedge: true);
    }
    if (_sparks.length > 180) return;
    for (var s = 0; s < 4; s++) {
      _sparks.add(
        Spark(
          x: drop.x,
          y: drop.y,
          vx: (_random.nextDouble() - 0.5) * 90,
          vy: -30 - _random.nextDouble() * 70,
          life: 0.4,
          size: drop.size * 0.28,
        ),
      );
    }
  }

  void _strikePot(Drop drop) {
    final size = screenSize;
    if (size != null) {
      final plant = _plantRect(size);
      final inMouth = (drop.x - plant.center.dx).abs() < plant.width * 0.09;
      if (inMouth) {
        _soilWet = math.min(1, _soilWet + 0.07);
        _absorb(0.011, drop.x, drop.y, fromSoil: true);
        if (_rings.length < 14) {
          _rings.add(Ring(x: drop.x, y: drop.y, maxR: drop.size * 3.4));
        }
      }
    }
    if (_sparks.length > 220) return;
    for (var s = 0; s < 3; s++) {
      _sparks.add(
        Spark(
          x: drop.x,
          y: drop.y,
          vx: (_random.nextDouble() - 0.5) * 70,
          vy: -40 - _random.nextDouble() * 50,
          life: 0.45,
          size: drop.size * 0.3,
        ),
      );
    }
  }

  void _spawnShower(Size size, Rect plant, Offset dir, double power) {
    final drawn = _jugDrawSize(size);
    final origin = _holeOnRose(size, drawn);

    final reach = _foliageGrowth;
    final atSoil = _random.nextDouble() < 0.34;
    final double targetX;
    if (atSoil) {
      targetX =
          plant.center.dx + (_random.nextDouble() - 0.5) * plant.width * 0.16;
    } else {
      final span = (0.62 + power * 0.34) * reach;
      final bandLeft = plant.center.dx - plant.width * span / 2;
      targetX = bandLeft + _random.nextDouble() * plant.width * span;
    }
    final drift = targetX - origin.dx;
    final speed = 0.9 + _random.nextDouble() * 0.25;

    _drops.add(
      Drop(
        x: origin.dx,
        y: origin.dy,
        vx: (dir.dx * (28 + power * 18) + drift * 0.7 * speed).clamp(
          -70.0,
          220.0,
        ),
        vy:
            (dir.dy * (28 + power * 18) + 42 + _random.nextDouble() * 18) *
            speed,
        size: (4.2 + _random.nextDouble() * 2.6) * plant.width / 360,
      ),
    );
  }

  void _absorb(double amount, double x, double y, {bool fromSoil = false}) {
    if (amount <= 0 || _growth >= 1) return;
    _growth = math.min(1, _growth + amount);
    _pulse = math.min(1, _pulse + (fromSoil ? 0.34 : 0.14));
    if (fromSoil || _random.nextDouble() < 0.22) {
      _riseMotes(
        x,
        y - 4,
        fromSoil ? 2 : 1,
        gold: fromSoil && _random.nextBool(),
      );
    }
    _markGrowth(x, y);
  }

  void _markGrowth(double x, double y) {
    const marks = [0.25, 0.5, 0.75, 1.0];
    final size = screenSize;
    while (_reached < marks.length && _growth >= marks[_reached]) {
      _reached++;
      _pulse = 1;
      if (!reduceMotion) {
        for (final frond in _fronds) {
          final sign = frond.centerU < 0.5 ? -1.0 : 1.0;
          frond.lean = (frond.lean + sign * 0.07).clamp(-0.2, 0.2);
        }
      }
      if (size != null) {
        final plant = _plantRect(size);
        final crown = _grownPoint(0.5, 0.32, plant);
        if (_rings.length < 16) {
          _rings.add(
            Ring(
              x: crown.dx,
              y: crown.dy,
              maxR: plant.width * 0.09,
              warm: true,
            ),
          );
        }
        _riseMotes(crown.dx, crown.dy, reduceMotion ? 2 : 8, gold: true);
      } else {
        _riseMotes(x, y, 4, gold: true);
      }
      HapticFeedback.mediumImpact();
    }
  }

  void _riseMotes(double x, double y, int count, {bool gold = false}) {
    final n = reduceMotion ? math.min(count, 1) : count;
    for (var i = 0; i < n; i++) {
      if (_motes.length >= 48) _motes.removeAt(0);
      final ang = -math.pi / 2 + (_random.nextDouble() - 0.5) * 1.1;
      final speed = 16 + _random.nextDouble() * 26;
      _motes.add(
        Mote(
          x: x + (_random.nextDouble() - 0.5) * 12,
          y: y,
          vx: math.cos(ang) * speed,
          vy: math.sin(ang) * speed,
          life: 1,
          size: 1.6 + _random.nextDouble() * 1.8,
          gold: gold || _random.nextDouble() > 0.72,
          phase: _random.nextDouble() * math.pi * 2,
        ),
      );
    }
  }

  void reset() {
    _drops.clear();
    _sparks.clear();
    _beads.clear();
    _rings.clear();
    _motes.clear();
    for (final frond in _fronds) {
      frond.angle = 0;
      frond.vel = 0;
      frond.lean = 0;
    }
    _time = 0;
    _spawnDebt = 0;
    _jugAngle = 0;
    _jugVel = 0;
    _dragging = false;
    _wasPouring = false;
    _lastPointer = null;
    showHint.value = true;
    _growth = 0;
    _shownGrowth = 0;
    _jugWater = 0.88;
    _soilWet = 0;
    _pulse = 0;
    _fullBreath = 0;
    _reached = 0;
    whisperBand.value = 0;
    HapticFeedback.lightImpact();
  }

  void _syncWhisper() {
    final g = _shownGrowth;
    final band = g >= 0.92
        ? 4
        : g >= 0.62
        ? 3
        : g >= 0.34
        ? 2
        : g >= 0.08
        ? 1
        : 0;
    if (band == whisperBand.value || isClosed) return;
    whisperBand.value = band;
  }

  String get caption {
    switch (whisperBand.value) {
      case 1:
        return 'The soil is drinking';
      case 2:
        return 'Leaves are opening';
      case 3:
        return 'Almost in full leaf';
      case 4:
        return 'Glossy and full';
      default:
        return 'Tilt the jug — water helps it grow';
    }
  }

  static const _sceneDrop = 0.08;
  static const _sceneLeft = 0.06;

  Rect backgroundRect(Size size) {
    if (size.isEmpty) return Rect.zero;
    const bgW = 839.0;
    const bgH = 1874.0;
    const trayU = 0.536;
    const trayV = 0.787;
    final cover = math.max(size.width / bgW, size.height / bgH);
    var dispW = bgW * cover;
    var dispH = bgH * cover;
    var top = (size.height - dispH) / 2 + size.height * _sceneDrop;
    if (top > 0) {
      final scale = (dispH + top) / dispH;
      dispW *= scale;
      dispH *= scale;
      top = 0;
    }
    var left = (size.width - dispW) / 2;
    final trayX = left + trayU * dispW - size.width * _sceneLeft;
    final trayY = top + trayV * dispH;
    var scale = 1.0;
    if (trayU > 0) scale = math.max(scale, trayX / (trayU * dispW));
    if (trayU < 1) {
      scale = math.max(scale, (size.width - trayX) / ((1 - trayU) * dispW));
    }
    if (trayV > 0) scale = math.max(scale, trayY / (trayV * dispH));
    if (trayV < 1) {
      scale = math.max(scale, (size.height - trayY) / ((1 - trayV) * dispH));
    }
    dispW *= scale;
    dispH *= scale;
    return Rect.fromLTWH(
      trayX - trayU * dispW,
      trayY - trayV * dispH,
      dispW,
      dispH,
    );
  }

  Rect _plantRect(Size size) {
    const trayU = 0.536;
    const trayV = 0.787;
    const potV = 0.925;
    final bg = backgroundRect(size);
    final tray = Offset(bg.left + trayU * bg.width, bg.top + trayV * bg.height);
    final side = math.min(size.width * 0.92, size.height * 0.72);
    return Rect.fromLTWH(
      tray.dx - side * 0.5,
      tray.dy - side * potV,
      side,
      side,
    );
  }

  void _stepJug(double dt) {
    if (_dragging) return;
    final acc = -10.0 * _jugAngle - 4.4 * _jugVel;
    _jugVel += acc * dt;
    final next = _jugAngle + _jugVel * dt;
    _jugAngle = next.clamp(_minTilt, _maxTilt);
    if ((_jugAngle <= _minTilt && _jugVel < 0) ||
        (_jugAngle >= _maxTilt && _jugVel > 0)) {
      _jugVel = 0;
    }
    if (_jugVel.abs() < 0.04 && _jugAngle.abs() < 0.02) {
      _jugAngle = 0;
      _jugVel = 0;
    }
  }

  Offset _jugPivot(Size size) {
    return Offset(size.width * 0.30, size.height * 0.24);
  }

  Size _jugDrawSize(Size size) {
    final width = math.min(size.width * 0.48, size.height * 0.30);
    return Size(width, width * 398 / 591);
  }

  Offset _spoutDirection() {
    const dx = _roseU - _pivotU;
    const dy = _roseV - _pivotV;
    final c = math.cos(_jugAngle);
    final s = math.sin(_jugAngle);
    final x = dx * c - dy * s;
    final y = dx * s + dy * c;
    final len = math.sqrt(x * x + y * y);
    return Offset(x / len, y / len);
  }

  double _pourPower(double dy) {
    return ((dy - _pourDy) / (1 - _pourDy)).clamp(0.0, 1.0);
  }

  Offset _holeOnRose(Size size, Size drawn) {
    final face = _jugLocal(_nozzleU, _nozzleV, drawn);
    final ang = _random.nextDouble() * math.pi * 2;
    final rad = math.sqrt(_random.nextDouble()) * drawn.width * 0.022;
    final local = face + Offset(math.cos(ang) * rad, math.sin(ang) * rad);
    return _rotateLocal(size, local);
  }

  Offset _rotateLocal(Size size, Offset local) {
    final pivot = _jugPivot(size);
    final c = math.cos(_jugAngle);
    final s = math.sin(_jugAngle);
    return Offset(
      pivot.dx + local.dx * c - local.dy * s,
      pivot.dy + local.dx * s + local.dy * c,
    );
  }

  void onPanStart(DragStartDetails details) {
    _dragging = true;
    _lastPointer = details.localPosition;
    if (showHint.value) showHint.value = false;
    HapticFeedback.selectionClick();
  }

  void onPanUpdate(DragUpdateDetails details) {
    final size = screenSize;
    final previous = _lastPointer;
    if (size == null || previous == null) return;
    final pivot = _jugPivot(size);
    final current = details.localPosition;
    final a0 = math.atan2(previous.dy - pivot.dy, previous.dx - pivot.dx);
    final a1 = math.atan2(current.dy - pivot.dy, current.dx - pivot.dx);
    var delta = a1 - a0;
    if (delta > math.pi) delta -= math.pi * 2;
    if (delta < -math.pi) delta += math.pi * 2;
    _jugAngle = (_jugAngle + delta).clamp(_minTilt, _maxTilt);
    _jugVel = 0;
    _lastPointer = current;
  }

  void onPanEnd(DragEndDetails details) {
    _dragging = false;
    _lastPointer = null;
  }

  void cancelDrag() {
    _dragging = false;
    _lastPointer = null;
  }

  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final image = _image;
    final plant = _plantRect(size);
    if (image != null &&
        _shader != null &&
        _positions != null &&
        _uvs != null &&
        _indices != null) {
      _paintShadow(canvas, plant);
      _paintAura(canvas, plant);
      _paintPlant(canvas, plant);
      _paintSoil(canvas, plant);
    }
    _paintJug(canvas, size);
    _paintNozzle(canvas, size);
    _paintWater(canvas);
  }

  void _paintAura(Canvas canvas, Rect plant) {
    final strength = (0.2 + 0.72 * _shownGrowth + 0.5 * _pulse).clamp(0.0, 1.4);
    final center = Offset(
      plant.center.dx,
      plant.top + plant.height * (0.64 - 0.18 * _shownGrowth),
    );
    final radius = plant.width * (0.15 + 0.16 * _shownGrowth);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFD7F0C8).withValues(alpha: 0.38 * strength),
            const Color(0xFFFFF3D2).withValues(alpha: 0.14 * strength),
            const Color(0x00FFF3D2),
          ],
          stops: const [0.0, 0.46, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }

  void _paintSoil(Canvas canvas, Rect plant) {
    if (_soilWet <= 0.02) return;
    final center = Offset(plant.center.dx, plant.top + plant.height * 0.785);
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: plant.width * 0.15,
        height: plant.width * 0.042,
      ),
      Paint()
        ..color = const Color(0xFF1C3A2A).withValues(alpha: 0.4 * _soilWet),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(-plant.width * 0.012, -plant.width * 0.006),
        width: plant.width * 0.055,
        height: plant.width * 0.014,
      ),
      Paint()
        ..color = const Color(0xFFF4FBFF).withValues(alpha: 0.32 * _soilWet),
    );
  }

  void _paintShadow(Canvas canvas, Rect plant) {
    final shadow = Rect.fromCenter(
      center: Offset(plant.center.dx, plant.top + plant.height * 0.905),
      width: plant.width * 0.26,
      height: plant.width * 0.05,
    );
    canvas.drawOval(
      shadow,
      Paint()
        ..color = const Color(0x332F3B32)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18),
    );
  }

  void _paintPlant(Canvas canvas, Rect plant) {
    final positions = _positions!;
    final uvs = _uvs!;
    for (var r = 0; r <= _rows; r++) {
      for (var c = 0; c <= _cols; c++) {
        final u = c / _cols;
        final v = r / _rows;
        final bent = _bend(u, v, plant);
        final i = (r * (_cols + 1) + c) * 2;
        positions[i] = bent.dx;
        positions[i + 1] = bent.dy;
      }
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: uvs,
      indices: _indices,
    );
    canvas.drawVertices(
      vertices,
      ui.BlendMode.srcOver,
      Paint()..shader = _shader,
    );
  }

  Offset _bend(double u, double v, Rect plant) {
    final grown = _grownPoint(u, v, plant);
    final x = grown.dx;
    final y = grown.dy;
    final height = _heightWeight(v);
    if (height <= 0) return Offset(x, y);

    var accAng = 0.0;
    var accW = 0.0;
    var pivX = 0.0;
    var pivY = 0.0;
    for (final frond in _fronds) {
      final along = math.exp(-math.pow((u - frond.centerU) / frond.sigma, 2));
      final weight = height * along;
      if (weight < 0.004) continue;
      accAng += frond.angle * weight;
      accW += weight;
      final pivot = _grownPoint(frond.pivotU, frond.pivotV, plant);
      pivX += pivot.dx * weight;
      pivY += pivot.dy * weight;
    }
    if (accW < 0.004) return Offset(x, y);

    final angle = (accAng / accW) * height;
    final px = pivX / accW;
    final py = pivY / accW;
    final dx = x - px;
    final dy = y - py;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(px + dx * c - dy * s, py + dx * s + dy * c);
  }

  double _heightWeight(double v) {
    if (v >= 0.70) return 0;
    if (v <= 0.22) return 1;
    final t = ((0.70 - v) / 0.48).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  void _paintJug(Canvas canvas, Size size) {
    final jug = _jug;
    if (jug == null) return;
    final pivot = _jugPivot(size);
    final drawn = _jugDrawSize(size);

    canvas.drawOval(
      Rect.fromCenter(
        center: pivot + Offset(0, drawn.height * 0.34),
        width: drawn.width * 0.42,
        height: drawn.height * 0.08,
      ),
      Paint()
        ..color = const Color(0x2A3A2E24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(_jugAngle);
    _paintGlassJug(canvas, jug, drawn);
    canvas.restore();
  }

  Offset _jugLocal(double u, double v, Size drawn) {
    return Offset((u - _pivotU) * drawn.width, (v - _pivotV) * drawn.height);
  }

  Path _jugInterior(Size drawn) {
    Offset p(double u, double v) => _jugLocal(u, v, drawn);
    const belly = <(double, double)>[
      (0.44, 0.10),
      (0.37, 0.13),
      (0.33, 0.18),
      (0.31, 0.26),
      (0.33, 0.36),
      (0.30, 0.46),
      (0.27, 0.56),
      (0.26, 0.66),
      (0.28, 0.76),
      (0.32, 0.84),
      (0.38, 0.88),
      (0.48, 0.90),
      (0.56, 0.86),
      (0.62, 0.76),
      (0.64, 0.66),
      (0.64, 0.56),
      (0.61, 0.48),
      (0.56, 0.40),
      (0.53, 0.30),
      (0.52, 0.20),
      (0.54, 0.13),
      (0.50, 0.09),
    ];
    final body = Path();
    for (var i = 0; i < belly.length; i++) {
      final o = p(belly[i].$1, belly[i].$2);
      if (i == 0) {
        body.moveTo(o.dx, o.dy);
      } else {
        body.lineTo(o.dx, o.dy);
      }
    }
    body.close();

    const tube = <(double, double)>[
      (0.56, 0.60),
      (0.62, 0.50),
      (0.68, 0.40),
      (0.73, 0.31),
      (0.78, 0.23),
      (0.81, 0.15),
      (0.838, 0.090),
    ];
    final pts = [for (final uv in tube) p(uv.$1, uv.$2)];
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final prev = pts[math.max(0, i - 1)];
      final next = pts[math.min(pts.length - 1, i + 1)];
      final delta = next - prev;
      final len = math.max(0.001, delta.distance);
      final n = Offset(-delta.dy / len, delta.dx / len);
      final radius = drawn.width * (i >= pts.length - 2 ? 0.032 : 0.017);
      left.add(pts[i] + n * radius);
      right.add(pts[i] - n * radius);
    }
    final channel = Path()..moveTo(left.first.dx, left.first.dy);
    for (final o in left.skip(1)) {
      channel.lineTo(o.dx, o.dy);
    }
    for (final o in right.reversed) {
      channel.lineTo(o.dx, o.dy);
    }
    channel.close();

    final rose = Path()
      ..addOval(
        Rect.fromCircle(
          center: p(_nozzleU, _nozzleV),
          radius: drawn.width * 0.040,
        ),
      );
    return Path.combine(
      PathOperation.union,
      Path.combine(PathOperation.union, body, channel),
      rose,
    );
  }

  void _paintGlassJug(Canvas canvas, ui.Image jug, Size drawn) {
    final bulbCenter = _jugLocal(0.40, 0.58, drawn);
    final interior = _jugInterior(drawn);
    final imageRect = Rect.fromLTWH(
      -_pivotU * drawn.width,
      -_pivotV * drawn.height,
      drawn.width,
      drawn.height,
    );
    final src = Rect.fromLTWH(
      0,
      0,
      jug.width.toDouble(),
      jug.height.toDouble(),
    );

    canvas.save();
    canvas.clipPath(interior);
    canvas.saveLayer(imageRect.inflate(drawn.width), Paint());
    canvas.rotate(-_jugAngle);
    final centerX =
        bulbCenter.dx * math.cos(_jugAngle) -
        bulbCenter.dy * math.sin(_jugAngle);
    final centerY =
        bulbCenter.dx * math.sin(_jugAngle) +
        bulbCenter.dy * math.cos(_jugAngle);
    final extent = drawn.height * 0.34;
    final surfaceY = centerY + extent * (1 - 2 * _jugWater);
    final waterRect = Rect.fromLTRB(
      -drawn.width * 2,
      surfaceY,
      drawn.width * 2,
      surfaceY + drawn.height * 2,
    );
    canvas.drawRect(
      waterRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xD6F4FBFF), Color(0xE68FD4EE), Color(0xF03E94BC)],
          stops: [0.0, 0.16, 1.0],
        ).createShader(waterRect),
    );
    canvas.drawLine(
      Offset(-drawn.width * 2, surfaceY),
      Offset(drawn.width * 2, surfaceY),
      Paint()
        ..color = const Color(0xF2FFFFFF)
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < 4; i++) {
      final bubbleY =
          surfaceY +
          10 +
          i * drawn.height * 0.045 +
          math.sin(_time * 1.3 + i) * 2;
      canvas.drawCircle(
        Offset(
          centerX + math.sin(_time * 0.7 + i * 1.4) * drawn.width * 0.04,
          bubbleY,
        ),
        1.6 + (i % 2) * 0.8,
        Paint()..color = const Color(0x99FFFFFF),
      );
    }
    canvas.rotate(_jugAngle);
    canvas.drawImageRect(
      jug,
      src,
      imageRect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..blendMode = BlendMode.dstIn,
    );
    canvas.restore();
    canvas.restore();

    canvas.drawImageRect(
      jug,
      src,
      imageRect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = const ColorFilter.matrix(<double>[
          0.72,
          0.12,
          0.16,
          0,
          36,
          0.08,
          0.74,
          0.18,
          0,
          40,
          0.06,
          0.14,
          0.80,
          0,
          48,
          0,
          0,
          0,
          0.46,
          0,
        ]),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: bulbCenter + Offset(-drawn.width * 0.05, -drawn.height * 0.06),
        width: drawn.width * 0.045,
        height: drawn.height * 0.22,
      ),
      Paint()..color = const Color(0x66FFFFFF),
    );
  }

  void _paintNozzle(Canvas canvas, Size size) {
    final dir = _spoutDirection();
    if (dir.dy <= _pourDy || _jugWater <= 0.08) return;
    final drawn = _jugDrawSize(size);
    final face = _jugLocal(_nozzleU, _nozzleV, drawn);
    for (var i = 0; i < 5; i++) {
      final ang = i / 5 * math.pi * 2 + 0.4;
      final local =
          face + Offset(math.cos(ang), math.sin(ang)) * drawn.width * 0.012;
      final hole = _rotateLocal(size, local);
      canvas.drawCircle(
        hole,
        math.max(1.1, drawn.width * 0.0045),
        Paint()..color = const Color(0xCCF4FBFF),
      );
    }
    _paintStream(canvas, size, drawn, dir);
  }

  void _paintStream(Canvas canvas, Size size, Size drawn, Offset dir) {
    final power = _pourPower(dir.dy);
    final origin = _rotateLocal(size, _jugLocal(_nozzleU, _nozzleV, drawn));
    final len = drawn.height * (0.28 + power * 0.22);
    final end = origin + Offset(dir.dx, dir.dy) * len;
    final side = Offset(-dir.dy, dir.dx);
    final width = 1.6 + power * 1.8;
    final path = Path()
      ..moveTo(origin.dx + side.dx * width, origin.dy + side.dy * width)
      ..quadraticBezierTo(
        origin.dx + dir.dx * len * 0.5 + side.dx * width * 0.45,
        origin.dy + dir.dy * len * 0.5 + side.dy * width * 0.45,
        end.dx,
        end.dy,
      )
      ..quadraticBezierTo(
        origin.dx + dir.dx * len * 0.5 - side.dx * width * 0.45,
        origin.dy + dir.dy * len * 0.5 - side.dy * width * 0.45,
        origin.dx - side.dx * width,
        origin.dy - side.dy * width,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xB8E7F6FF));
    canvas.drawLine(
      origin,
      end,
      Paint()
        ..color = const Color(0x88FFFFFF)
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintWater(Canvas canvas) {
    for (final ring in _rings) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.warm ? 1.8 : 1.2
        ..color =
            (ring.warm ? const Color(0xFFE7C56A) : const Color(0xFF7EC8E3))
                .withValues(alpha: (ring.warm ? 0.55 : 0.4) * ring.life);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(ring.x, ring.y),
          width: ring.maxR * (1.1 - ring.life) * 2.4,
          height: ring.maxR * (1.1 - ring.life) * 0.7,
        ),
        paint,
      );
    }

    for (final bead in _beads) {
      final shine = 0.72 + 0.28 * math.sin(_time * 2.6 + bead.glint);
      final alpha = (0.88 * bead.life * shine).clamp(0.0, 1.0);
      if (bead.onLedge) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(bead.x, bead.y),
            width: bead.size * 2.4,
            height: bead.size * 1.1,
          ),
          Paint()..color = const Color(0xFFB9E6F8).withValues(alpha: alpha),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(bead.x - bead.size * 0.3, bead.y - bead.size * 0.12),
            width: bead.size * 0.7,
            height: bead.size * 0.35,
          ),
          Paint()
            ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha * 0.8),
        );
      } else {
        canvas.drawCircle(
          Offset(bead.x, bead.y),
          bead.size,
          Paint()..color = const Color(0xFFD7F4FF).withValues(alpha: alpha),
        );
        canvas.drawCircle(
          Offset(bead.x - bead.size * 0.28, bead.y - bead.size * 0.32),
          bead.size * 0.32,
          Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha),
        );
      }
    }

    for (final drop in _drops) {
      _paintDrop(canvas, drop);
    }

    for (final spark in _sparks) {
      canvas.drawCircle(
        Offset(spark.x, spark.y),
        spark.size * spark.life.clamp(0.2, 1),
        Paint()
          ..color = const Color(
            0xFFD7F3FF,
          ).withValues(alpha: spark.life.clamp(0, 1)),
      );
    }

    for (final mote in _motes) {
      final alpha = (mote.life * 0.9).clamp(0.0, 1.0);
      final color = mote.gold
          ? const Color(0xFFFFE7A8)
          : const Color(0xFFD8F5C9);
      canvas.drawCircle(
        Offset(mote.x, mote.y),
        mote.size * (0.65 + 0.35 * mote.life),
        Paint()..color = color.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        Offset(mote.x - mote.size * 0.22, mote.y - mote.size * 0.22),
        mote.size * 0.32,
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha * 0.85),
      );
    }
  }

  void _paintDrop(Canvas canvas, Drop drop) {
    final speed = math.sqrt(drop.vx * drop.vx + drop.vy * drop.vy);
    final stretch = (speed / 900).clamp(0.0, 0.45);
    final h = drop.size * (1.15 + stretch);
    final w = drop.size * 0.7;
    final angle = math.atan2(drop.vy, drop.vx) - math.pi / 2;

    canvas.save();
    canvas.translate(drop.x, drop.y);
    canvas.rotate(angle);

    final tail = Paint()
      ..color = const Color(0x557EC8E3)
      ..strokeWidth = w * 0.9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, -h * 0.2), Offset(0, -h * 1.15), tail);

    canvas.drawCircle(
      Offset(0, h * 0.05),
      w * 1.15,
      Paint()..color = const Color(0x4496D4EE),
    );
    final path = Path()
      ..moveTo(0, -h)
      ..quadraticBezierTo(w, -h * 0.05, 0, h * 0.42)
      ..quadraticBezierTo(-w, -h * 0.05, 0, -h)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xE67EC8EE));
    final core = Path()
      ..moveTo(0, -h * 0.55)
      ..quadraticBezierTo(w * 0.45, -h * 0.02, 0, h * 0.22)
      ..quadraticBezierTo(-w * 0.45, -h * 0.02, 0, -h * 0.55)
      ..close();
    canvas.drawPath(core, Paint()..color = const Color(0x66FFFFFF));
    canvas.drawCircle(
      Offset(-w * 0.22, -h * 0.28),
      math.max(0.8, w * 0.28),
      Paint()..color = const Color(0xF2FFFFFF),
    );
    canvas.restore();
  }
}
