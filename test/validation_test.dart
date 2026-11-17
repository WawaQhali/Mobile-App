import 'package:flutter_test/flutter_test.dart';
import 'package:wawa_qhali/data/db.dart';
import 'package:wawa_qhali/services/validation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('si se ve el rostro, avisa pero no bloquea el análisis', () async {
    await Db.cargar();
    Db.instance.demo['validacion'] = 'con_rostro';

    final checks = await ValidacionService.validar(null);
    final rostro = checks.firstWhere((c) => c.id == 'rostro');

    expect(rostro.ok, isFalse);
    expect(rostro.bloquea, isFalse);
    expect(checks.where((c) => !c.ok && c.bloquea), isEmpty);
  });
}
