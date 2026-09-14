import 'package:flutter/material.dart';
import '../services/api.dart';

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
  String? error;

  @override void dispose(){user.dispose();pass.dispose();super.dispose();}

  Future<void> submit() async{
    if(busy)return;
    setState((){busy=true;error=null;});
    try{
      await widget.api.login(user.text.trim(),pass.text);
      pass.clear();
      await widget.onAuthenticated();
    }catch(_){
      if(mounted)setState(()=>error='Não foi possível entrar. Verifique suas credenciais.');
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    body:Center(
      child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:420),
        child:Padding(
          padding:const EdgeInsets.all(24),
          child:Column(
            mainAxisSize:MainAxisSize.min,
            children:[
              const Text('LUME',style:TextStyle(fontSize:32,fontWeight:FontWeight.bold)),
              if(widget.notice!=null)Padding(
                padding:const EdgeInsets.only(top:16),
                child:Text(widget.notice!,textAlign:TextAlign.center),
              ),
              const SizedBox(height:24),
              TextField(controller:user,autofillHints:const[AutofillHints.username],decoration:const InputDecoration(labelText:'Usuário')),
              const SizedBox(height:12),
              TextField(controller:pass,obscureText:true,autofillHints:const[AutofillHints.password],onSubmitted:(_)=>submit(),decoration:const InputDecoration(labelText:'Senha')),
              if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!)),
              const SizedBox(height:20),
              FilledButton(
                onPressed:busy?null:submit,
                child:busy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Text('Entrar'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
