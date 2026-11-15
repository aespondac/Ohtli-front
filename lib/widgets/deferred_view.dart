import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Muestra una pantalla de una biblioteca cargada de forma diferida (`import … deferred as`):
/// su código no viaja en la descarga inicial de la app y se pide la primera vez que se abre.
class DeferredView extends StatefulWidget {
  const DeferredView({super.key, required this.load, required this.builder});

  /// `biblioteca.loadLibrary`
  final Future<void> Function() load;
  final WidgetBuilder builder;

  @override
  State<DeferredView> createState() => _DeferredViewState();
}

class _DeferredViewState extends State<DeferredView> {
  // Una carga por biblioteca: volver a la pantalla no la vuelve a pedir
  static final Map<Object, Future<void>> _loads = {};
  // Bibliotecas ya cargadas: se dibujan al instante, sin un cuadro de espera
  static final Set<Object> _loaded = {};
  late Future<void> _future;

  Future<void> _start() =>
      _loads.putIfAbsent(widget.load, () => widget.load().then((_) => _loaded.add(widget.load)));

  @override
  void initState() {
    super.initState();
    _future = _start();
  }

  void _retry() {
    _loads.remove(widget.load);
    setState(() => _future = _start());
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded.contains(widget.load)) return widget.builder(context);
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError) {
          return widget.builder(context);
        }
        return Scaffold(
          backgroundColor: OhtliColors.cloudDancer,
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('No se pudo cargar esta sección.', style: TextStyle(color: OhtliColors.onyx)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _retry, child: const Text('Reintentar')),
                    ],
                  )
                : const CircularProgressIndicator(color: OhtliColors.stormyTeal),
          ),
        );
      },
    );
  }
}
