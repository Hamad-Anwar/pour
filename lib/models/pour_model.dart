class Frond {
  Frond({
    required this.centerU,
    required this.pivotU,
    required this.pivotV,
    required this.sigma,
    required this.phase,
    required this.speed,
  });

  final double centerU;
  final double pivotU;
  final double pivotV;
  final double sigma;
  final double phase;
  final double speed;

  double angle = 0;
  double vel = 0;
  double lean = 0;
}

class Drop {
  Drop({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
  });

  double x;
  double y;
  double vx;
  double vy;
  double size;
}

class Spark {
  Spark({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
  });

  double x;
  double y;
  double vx;
  double vy;
  double life;
  double size;
}

class Bead {
  Bead({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
    required this.glint,
    this.u,
    this.v,
    this.onLedge = false,
  });

  double x;
  double y;
  double vx;
  double vy;
  double life;
  double size;
  double glint;
  double? u;
  double? v;
  bool onLedge;
}

class Ring {
  Ring({
    required this.x,
    required this.y,
    required this.maxR,
    this.warm = false,
  });

  double x;
  double y;
  double life = 1;
  final double maxR;
  final bool warm;
}

class Mote {
  Mote({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
    required this.gold,
    required this.phase,
  });

  double x;
  double y;
  double vx;
  double vy;
  double life;
  double size;
  bool gold;
  final double phase;
}
