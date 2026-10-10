import 'package:flutter/material.dart';

/// Mantém a largura do card e permite arrastar as colunas no celular.
class ResponsiveTableContainer extends StatefulWidget {
  const ResponsiveTableContainer({
    super.key,
    required this.child,
    this.controller,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  @override
  State<ResponsiveTableContainer> createState() =>
      _ResponsiveTableContainerState();
}

class _ResponsiveTableContainerState extends State<ResponsiveTableContainer> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final controller = widget.controller ?? _controller;
      final horizontalPadding = widget.padding
          .resolve(Directionality.of(context))
          .horizontal;
      final minWidth = (constraints.maxWidth - horizontalPadding).clamp(
        0.0,
        double.infinity,
      );

      return Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: widget.child,
          ),
        ),
      );
    },
  );
}
