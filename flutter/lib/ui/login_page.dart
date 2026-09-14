import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'lume_theme.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  final LumeApi api;
  final Future<void> Function() onAuthenticated;
  final String? notice;
  const LoginPage({super.key,required this.api,required this.onAuthenticated,this.notice});
  @override State<LoginPage> createState()=>_LoginPageState();
}

class _LoginPageState extends State<LoginPage>{
  final user=TextEditingController();
  final pass=TextEditingController();
  bool busy=false;
  bool hidePassword=true;
  String? error;
  String? localNotice;

  @override void dispose(){user.dispose();pass.dispose();super.dispose();}

  String _loginError(Object exception){
    if(exception is ApiException){
      try{
        final body=jsonDecode(exception.body??'');
        if(body is Map && body['error']=='account_disabled')return 'Esta conta foi desligada pelo administrador.';
      }catch(_){ }
    }
    return 'Não foi possível entrar. Confira o usuário e a senha.';
  }

  Future<void> submit() async{
    if(busy)return;
    if(user.text.trim().isEmpty||pass.text.isEmpty){
      setState(()=>error='Informe seu usuário e sua senha.');
      return;
    }
    setState((){busy=true;error=null;localNotice=null;});
    try{
      await widget.api.login(user.text.trim().toLowerCase(),pass.text);
      pass.clear();
      await widget.onAuthenticated();
    }catch(exception){
      if(mounted)setState(()=>error=_loginError(exception));
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  Future<void> createAccount() async{
    if(busy)return;
    final created=await Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>SignupPage(api:widget.api)));
    if(created==null||!mounted)return;
    user.text=created;
    pass.clear();
    setState((){error=null;localNotice='Conta criada. Agora, entre com sua senha.';});
  }

  @override Widget build(BuildContext context)=>Scaffold(
    body:Stack(children:[
      const Positioned.fill(child:_LoginBackdrop()),
      SafeArea(child:Center(child:SingleChildScrollView(
        padding:const EdgeInsets.all(20),
        child:ConstrainedBox(
          constraints:const BoxConstraints(maxWidth:460),
          child:Column(children:[
            const _LoginBrand(),
            const SizedBox(height:28),
            Card(child:Padding(
              padding:const EdgeInsets.fromLTRB(22,26,22,22),
              child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                Text('Entre para continuar',style:Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height:7),
                Text('Seu progresso, sua estante e seus downloads ficam reunidos aqui.',style:Theme.of(context).textTheme.bodyMedium),
                if(widget.notice!=null||localNotice!=null)Container(
                  margin:const EdgeInsets.only(top:16),
                  padding:const EdgeInsets.all(12),
                  decoration:BoxDecoration(color:Theme.of(context).colorScheme.secondaryContainer,borderRadius:BorderRadius.circular(12)),
                  child:Text(localNotice??widget.notice!,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w700)),
                ),
                const SizedBox(height:22),
                Semantics(
                  label:'Usuário',
                  textField:true,
                  child:TextField(
                    controller:user,
                    autocorrect:false,
                    textCapitalization:TextCapitalization.none,
                    autofillHints:const[AutofillHints.username],
                    decoration:const InputDecoration(labelText:'Usuário',prefixIcon:Icon(Icons.alternate_email)),
                  ),
                ),
                const SizedBox(height:13),
                Semantics(
                  label:'Senha',
                  textField:true,
                  child:TextField(
                    controller:pass,
                    obscureText:hidePassword,
                    autofillHints:const[AutofillHints.password],
                    onSubmitted:(_)=>submit(),
                    decoration:InputDecoration(
                      labelText:'Senha',
                      prefixIcon:const Icon(Icons.lock_outline),
                      suffixIcon:IconButton(
                        tooltip:hidePassword?'Mostrar senha':'Ocultar senha',
                        onPressed:()=>setState(()=>hidePassword=!hidePassword),
                        icon:Icon(hidePassword?Icons.visibility_outlined:Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                ),
                if(error!=null)Padding(
                  padding:const EdgeInsets.only(top:13),
                  child:Text(error!,textAlign:TextAlign.center,style:TextStyle(color:Theme.of(context).colorScheme.error,fontWeight:FontWeight.w700)),
                ),
                const SizedBox(height:20),
                FilledButton(
                  onPressed:busy?null:submit,
                  child:busy?const SizedBox(width:21,height:21,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Text('Entrar no LUME'),
                ),
                const SizedBox(height:10),
                OutlinedButton(onPressed:busy?null:createAccount,child:const Text('Criar minha conta')),
                const SizedBox(height:13),
                Text('Nenhum e-mail é necessário.',textAlign:TextAlign.center,style:Theme.of(context).textTheme.bodySmall),
              ]),
            )),
          ]),
        ),
      ))),
    ]),
  );
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();
  @override Widget build(BuildContext context)=>Column(children:[
    const LumeMark(size:66,color:Color(0xFFF1C47F)),
    const SizedBox(height:13),
    Text('LUME',style:Theme.of(context).textTheme.displayMedium?.copyWith(color:Colors.white,letterSpacing:5)),
    const SizedBox(height:4),
    Text('BIBLIOTECA ESTUDANTIL',style:Theme.of(context).textTheme.labelMedium?.copyWith(color:Colors.white.withValues(alpha:.72),letterSpacing:2)),
  ]);
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();
  @override Widget build(BuildContext context)=>DecoratedBox(
    decoration:const BoxDecoration(
      gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF314A3B),LumePalette.night,Color(0xFF522B22)]),
    ),
    child:CustomPaint(painter:_BackdropPainter()),
  );
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();
  @override void paint(Canvas canvas,Size size){
    final paint=Paint()..color=Colors.white.withValues(alpha:.055)..style=PaintingStyle.stroke..strokeWidth=1;
    for(var i=0;i<5;i++){
      final inset=24.0+i*38;
      canvas.drawOval(Rect.fromLTWH(size.width*.48-inset,size.height*.04-inset,size.width*.7+inset*2,size.width*.7+inset*2),paint);
    }
    final ember=Paint()..color=LumePalette.ember.withValues(alpha:.13);
    canvas.drawCircle(Offset(size.width*.08,size.height*.83),size.width*.34,ember);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}
