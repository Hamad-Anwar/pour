import 'package:get/get.dart';

import 'pour_controller.dart';

class PourBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(PourController());
  }
}
