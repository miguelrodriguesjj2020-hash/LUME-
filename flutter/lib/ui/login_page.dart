import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api.dart';
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
  String? error;
  String? localNotice;

  @override void dispose(){user.dispose();pass.dispose();super.dispose();}

  String _loginError(Object e){
    if(e is ApiException){
      try{
        final j=jsonDecode(e.body??'');
        if(j is Map && j['error']=='account_disabled')return 'Esta conta foi desligada pelo administrador.';
      }catch(_){ }
    }
    return 'Não foi possível entrar. Verifique suas credenciais.';
  }

  Future<void> submit() async{
    if(busy)return;
    setState((){busy=true;error=null;localNotice=null;});
    try{
      await widget.api.login(user.text.trim(),pass.text);
      pass.clear();
      await widget.onAuthenticated();
    }catch(e){
      if(mounted)setState(()=>error=_loginError(e));
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
    setState((){
      error=null;
      localNotice='Conta criada. Entre com seu usuário e senha.';
    });
  }

  @override Widget build(BuildContext context)=>Scaffold(
    body:Center(
      child:SingleChildScrollView(
        padding:const EdgeInsets.all(24),
        child:ConstrainedBox(
          constraints:const BoxConstraints(maxWidth:420),
          child:Column(
            mainAxisSize:MainAxisSize.min,
            children:[
              const Text('LUME',style:TextStyle(fontSize:32,fontWeight:FontWeight.bold)),
              const SizedBox(height:8),
              Text('Sua biblioteca estudantil',style:Theme.of(context).textTheme.bodyLarge),
              if(widget.notice!=null||localNotice!=null)Padding(
                padding:const EdgeInsets.only(top:16),
                child:Text(localNotice??widget.notice!,textAlign:TextAlign.center),
              ),
              const SizedBox(height:24),
              Semantics(
                label:'Usuário',
                textField:true,
                child:TextField(controller:user,autocorrect:false,textCapitalization:TextCapitalization.none,autofillHints:const[AutofillHints.username],decoration:const InputDecoration(labelText:'Usuário',border:OutlineInputBorder())),
              ),
              const SizedBox(height:12),
              Semantics(
                label:'Senha',
                textField:true,
                child:TextField(controller:pass,obscureText:true,autofillHints:const[AutofillHints.password],onSubmitted:(_)=>submit(),decoration:const InputDecoration(labelText:'Senha',border:OutlineInputBorder())),
              ),
              if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,textAlign:TextAlign.center,style:TextStyle(color:Theme.of(context).colorScheme.error))),
              const SizedBox(height:20),
              SizedBox(width:double.infinity,child:FilledButton(
                onPressed:busy?null:submit,
                child:busy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Text('Entrar'),
              )),
              const SizedBox(height:10),
              SizedBox(width:double.infinity,child:OutlinedButton(
                onPressed:busy?null:createAccount,
                child:const Text('Criar conta'),
              )),
            ],
          ),
        ),
      ),
    ),
  );
}
