import 'package:flutter/material.dart';

abstract final class LumePalette {
  static const paper=Color(0xFFF3EFE5);
  static const paperDeep=Color(0xFFE7DFCF);
  static const ink=Color(0xFF1D211E);
  static const inkSoft=Color(0xFF4F554F);
  static const ember=Color(0xFFC45736);
  static const emberDeep=Color(0xFF8D3522);
  static const forest=Color(0xFF405849);
  static const brass=Color(0xFFB58B43);
  static const night=Color(0xFF17201C);
}

abstract final class LumeTheme {
  static ThemeData light(){
    const scheme=ColorScheme.light(
      primary:LumePalette.ember,
      onPrimary:Colors.white,
      primaryContainer:Color(0xFFF5D8CB),
      onPrimaryContainer:LumePalette.emberDeep,
      secondary:LumePalette.forest,
      onSecondary:Colors.white,
      secondaryContainer:Color(0xFFDCE7DE),
      onSecondaryContainer:LumePalette.night,
      tertiary:LumePalette.brass,
      surface:LumePalette.paper,
      onSurface:LumePalette.ink,
      surfaceContainerHighest:LumePalette.paperDeep,
      onSurfaceVariant:LumePalette.inkSoft,
      outline:Color(0xFF817B70),
      outlineVariant:Color(0xFFD0C7B7),
      error:Color(0xFFB3261E),
      onError:Colors.white,
    );
    final base=ThemeData(useMaterial3:true,colorScheme:scheme);
    TextStyle editorial(TextStyle? source,{double? size,FontWeight? weight,double? height,double? spacing})=>(source??const TextStyle()).copyWith(
      fontFamily:'serif',fontSize:size,fontWeight:weight,height:height,letterSpacing:spacing,color:LumePalette.ink,
    );
    final text=base.textTheme.copyWith(
      displayLarge:editorial(base.textTheme.displayLarge,size:54,weight:FontWeight.w700,height:.98,spacing:-1.8),
      displayMedium:editorial(base.textTheme.displayMedium,size:42,weight:FontWeight.w700,height:1.02,spacing:-1.2),
      headlineLarge:editorial(base.textTheme.headlineLarge,size:34,weight:FontWeight.w700,height:1.06,spacing:-.7),
      headlineMedium:editorial(base.textTheme.headlineMedium,size:28,weight:FontWeight.w700,height:1.08,spacing:-.4),
      headlineSmall:editorial(base.textTheme.headlineSmall,size:23,weight:FontWeight.w700,height:1.12),
      titleLarge:editorial(base.textTheme.titleLarge,size:21,weight:FontWeight.w700,height:1.15),
      titleMedium:(base.textTheme.titleMedium??const TextStyle()).copyWith(fontWeight:FontWeight.w700,height:1.2,color:LumePalette.ink),
      bodyLarge:(base.textTheme.bodyLarge??const TextStyle()).copyWith(height:1.45,color:LumePalette.ink),
      bodyMedium:(base.textTheme.bodyMedium??const TextStyle()).copyWith(height:1.4,color:LumePalette.ink),
      bodySmall:(base.textTheme.bodySmall??const TextStyle()).copyWith(height:1.35,color:LumePalette.inkSoft),
      labelLarge:(base.textTheme.labelLarge??const TextStyle()).copyWith(fontWeight:FontWeight.w700,letterSpacing:.15),
    );
    return base.copyWith(
      scaffoldBackgroundColor:LumePalette.paper,
      textTheme:text,
      appBarTheme:const AppBarTheme(
        backgroundColor:LumePalette.paper,
        foregroundColor:LumePalette.ink,
        surfaceTintColor:Colors.transparent,
        elevation:0,
        centerTitle:false,
      ),
      cardTheme:CardThemeData(
        color:const Color(0xFFFAF7F0),
        surfaceTintColor:Colors.transparent,
        elevation:0,
        margin:EdgeInsets.zero,
        shape:RoundedRectangleBorder(
          borderRadius:BorderRadius.circular(18),
          side:const BorderSide(color:Color(0x1F1D211E)),
        ),
      ),
      navigationBarTheme:NavigationBarThemeData(
        height:72,
        backgroundColor:const Color(0xFFFAF7F0),
        indicatorColor:scheme.primaryContainer,
        surfaceTintColor:Colors.transparent,
        labelTextStyle:WidgetStateProperty.resolveWith((states)=>TextStyle(
          fontWeight:states.contains(WidgetState.selected)?FontWeight.w800:FontWeight.w600,
          color:states.contains(WidgetState.selected)?LumePalette.emberDeep:LumePalette.inkSoft,
        )),
      ),
      inputDecorationTheme:InputDecorationTheme(
        filled:true,
        fillColor:const Color(0xFFFAF7F0),
        border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:const BorderSide(color:Color(0x331D211E))),
        enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:const BorderSide(color:Color(0x261D211E))),
        focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:const BorderSide(color:LumePalette.ember,width:1.5)),
      ),
      chipTheme:base.chipTheme.copyWith(
        side:const BorderSide(color:Color(0x2E1D211E)),
        selectedColor:scheme.primaryContainer,
        backgroundColor:const Color(0xFFFAF7F0),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(999)),
        labelStyle:const TextStyle(fontWeight:FontWeight.w700),
      ),
      filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(
        minimumSize:const Size(48,48),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
        textStyle:const TextStyle(fontWeight:FontWeight.w800),
      )),
      outlinedButtonTheme:OutlinedButtonThemeData(style:OutlinedButton.styleFrom(
        minimumSize:const Size(48,48),
        side:const BorderSide(color:Color(0x521D211E)),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
        textStyle:const TextStyle(fontWeight:FontWeight.w800),
      )),
      dividerColor:const Color(0x241D211E),
    );
  }
}

class LumeMark extends StatelessWidget {
  final double size;
  final Color? color;
  const LumeMark({super.key,this.size=38,this.color});

  @override Widget build(BuildContext context)=>Semantics(
    label:'Símbolo LUME, livro e chama',
    child:CustomPaint(
      size:Size.square(size),
      painter:_LumeMarkPainter(color??Theme.of(context).colorScheme.primary),
    ),
  );
}

class _LumeMarkPainter extends CustomPainter {
  final Color color;
  const _LumeMarkPainter(this.color);

  @override void paint(Canvas canvas,Size size){
    final stroke=Paint()..color=color..style=PaintingStyle.stroke..strokeWidth=size*.075..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round;
    final left=Path()
      ..moveTo(size*.12,size*.28)
      ..quadraticBezierTo(size*.34,size*.2,size*.5,size*.38)
      ..lineTo(size*.5,size*.82)
      ..quadraticBezierTo(size*.34,size*.64,size*.12,size*.72)
      ..close();
    final right=Path()
      ..moveTo(size*.88,size*.28)
      ..quadraticBezierTo(size*.66,size*.2,size*.5,size*.38)
      ..lineTo(size*.5,size*.82)
      ..quadraticBezierTo(size*.66,size*.64,size*.88,size*.72)
      ..close();
    canvas.drawPath(left,stroke);canvas.drawPath(right,stroke);
    final flame=Path()
      ..moveTo(size*.5,size*.08)
      ..cubicTo(size*.64,size*.22,size*.61,size*.32,size*.5,size*.38)
      ..cubicTo(size*.39,size*.31,size*.37,size*.21,size*.5,size*.08)
      ..close();
    canvas.drawPath(flame,Paint()..color=color..style=PaintingStyle.fill);
  }

  @override bool shouldRepaint(covariant _LumeMarkPainter oldDelegate)=>oldDelegate.color!=color;
}
