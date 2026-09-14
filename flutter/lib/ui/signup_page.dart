import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api.dart';

class SignupPage extends StatefulWidget {
  final LumeApi api;
  const SignupPage({super.key,required this.api});
  @override State<SignupPage> createState()=>_SignupPageState();
}

class _SignupPageState extends State<SignupPage>{
  final name=TextEditingController();
  final user=TextEditingController();
  final pass=TextEditingController();
  final className=TextEditingController();
  bool busy=false;
  bool hidePassword=true;
  String? error;

  @override void dispose(){name.dispose();user.dispose();pass.dispose();className.dispose();super.dispose();}

  String? _validate(){
    if(name.text.trim().length<2)return 'Informe seu nome verdadeiro.';
    final u=user.text.trim().toLowerCase();
    if(!RegExp(r'^[a-z0-9._-]{3,24}$').hasMatch(u))return 'O usuário deve ter de 3 a 24 caracteres: letras, números, ponto, _ ou -.';
    if(pass.text.length<8)return 'A senha precisa ter pelo menos 8 caracteres.';
    if(className.text.trim().isEmpty)return 'Informe sua turma.';
    return null;
  }

  String _serverError(Object e){
    if(e is ApiException){
      try{
        final j=jsonDecode(e.body??'');
        if(j is Map){
          switch(j['error']){
            case 'user_limit_reached':
              return 'Número máximo de usuários atingido, busque contato com um membro do grêmio para entender.';
            case 'username_taken':
              return 'Este usuário já existe. Escolha outro nome de usuário.';
            case 'invalid_registration':
              return '${j['message']??'Confira os dados informados.'}';
          }
        }
      }catch(_){ }
    }
    return 'Não foi possível criar a conta agora. Tente novamente.';
  }

  Future<void> submit() async{
    if(busy)return;
    final localError=_validate();
    if(localError!=null){setState(()=>error=localError);return;}
    setState((){busy=true;error=null;});
    final normalized=user.text.trim().toLowerCase();
    try{
      await widget.api.register(
        fullName:name.text.trim(),
        username:normalized,
        password:pass.text,
        className:className.text.trim(),
      );
      if(mounted)Navigator.pop(context,normalized);
    }catch(e){
      if(mounted)setState(()=>error=_serverError(e));
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Criar conta')),
    body:SafeArea(child:SingleChildScrollView(
      padding:const EdgeInsets.all(24),
      child:Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:480),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('Seu perfil no LUME',style:Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height:8),
          const Text('Preencha apenas os dados abaixo. Nenhum e-mail é necessário.'),
          const SizedBox(height:24),
          TextField(controller:name,textCapitalization:TextCapitalization.words,autofillHints:const[AutofillHints.name],decoration:const InputDecoration(labelText:'Nome verdadeiro',border:OutlineInputBorder())),
          const SizedBox(height:14),
          TextField(controller:user,autocorrect:false,textCapitalization:TextCapitalization.none,autofillHints:const[AutofillHints.newUsername],decoration:const InputDecoration(labelText:'Usuário',hintText:'ex.: joao.silva',border:OutlineInputBorder())),
          const SizedBox(height:14),
          TextField(controller:pass,obscureText:hidePassword,autofillHints:const[AutofillHints.newPassword],decoration:InputDecoration(labelText:'Senha',border:const OutlineInputBorder(),suffixIcon:IconButton(onPressed:()=>setState(()=>hidePassword=!hidePassword),icon:Icon(hidePassword?Icons.visibility_outlined:Icons.visibility_off_outlined)))),
          const SizedBox(height:14),
          TextField(controller:className,textCapitalization:TextCapitalization.characters,onSubmitted:(_)=>submit(),decoration:const InputDecoration(labelText:'Turma',hintText:'ex.: 2º A',border:OutlineInputBorder())),
          if(error!=null)Padding(padding:const EdgeInsets.only(top:16),child:Text(error!,textAlign:TextAlign.center,style:TextStyle(color:Theme.of(context).colorScheme.error,fontWeight:FontWeight.w600))),
          const SizedBox(height:24),
          FilledButton.icon(onPressed:busy?null:submit,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.person_add_alt_1),label:const Text('Criar minha conta')),
        ]),
      )),
    )),
  );
}
