import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/pour_controller.dart';

class PourView extends GetView<PourController> {
  const PourView({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3E6D0),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          controller.screenSize = size;
          controller.reduceMotion = reduceMotion;
          final bg = controller.backgroundRect(size);
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: bg.left,
                top: bg.top,
                width: bg.width,
                height: bg.height,
                child: const Image(
                  image: AssetImage('assets/images/bg.png'),
                  fit: BoxFit.fill,
                ),
              ),
              Positioned.fill(
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: controller.onPanStart,
                    onPanUpdate: controller.onPanUpdate,
                    onPanEnd: controller.onPanEnd,
                    onPanCancel: controller.cancelDrag,
                    child: CustomPaint(
                      painter: PourPainter(controller),
                      size: size,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Obx(() {
                  if (controller.ready.value ||
                      controller.errorMessage.value != null) {
                    return const SizedBox.shrink();
                  }
                  return const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Color(0xFF3E6B4F),
                      ),
                    ),
                  );
                }),
              ),
              Positioned.fill(
                child: Obx(() {
                  final message = controller.errorMessage.value;
                  if (message == null) return const SizedBox.shrink();
                  return Center(
                    child: Text(
                      message,
                      style: const TextStyle(color: Color(0xFF3E6B4F)),
                    ),
                  );
                }),
              ),
              Positioned(
                top: 8,
                right: 12,
                child: SafeArea(
                  child: Tooltip(
                    message: 'Reset',
                    child: Material(
                      color: const Color(0xE8FFF8EE),
                      shape: const CircleBorder(
                        side: BorderSide(color: Color(0x333E6B4F)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: controller.reset,
                        child: const SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(
                            Icons.restart_alt_rounded,
                            color: Color(0xFF3E6B4F),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 22,
                child: IgnorePointer(
                  child: Obx(() {
                    final caption = controller.caption;
                    final visible =
                        (controller.whisperBand.value > 0 ||
                            controller.showHint.value) &&
                        controller.ready.value;
                    return AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 350),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        child: Text(
                          caption,
                          key: ValueKey(caption),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF5E7564),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PourPainter extends CustomPainter {
  PourPainter(this.controller) : super(repaint: controller.frame);

  final PourController controller;

  @override
  void paint(Canvas canvas, Size size) => controller.paint(canvas, size);

  @override
  bool shouldRepaint(covariant PourPainter oldDelegate) => false;
}
