import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/app_services.dart';

class AdminUsersPage extends StatefulWidget{
  final AppServices services;
  const AdminUsersPage({super.key,required this.services});
  @override State<AdminUsersPage> createState()=>_AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage>{
  bool loading=true;
  String? error;
  int activeCount=0;
  int maxUsers=91;
  List<Map<String,dynamic>> users=[];
  final changing=<String>{};

  @override void initState(){super.initState();_load();}

  String _message(Object e){
    if(e is ApiException){
      try{
        final j=jsonDecode(e.body??'');
        if(j is Map && j['error']=='user_limit_reached')return 'Número máximo de usuários atingido, busque contato com um membro do grêmio para entender.';
      }catch(_){ }
    }
    return 'Não foi possível atualizar este usuário.';
  }

  Future<void> _load() async{
    try{
      final j=await widget.services.api.adminUsers();
      users=(j['users'] as List? ?? const[]).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
      activeCount=(j['activeCount'] as num?)?.toInt()??0;
      maxUsers=(j['maxUsers'] as num?)?.toInt()??91;
      error=null;
    }catch(e){error='$e';}
    if(mounted)setState(()=>loading=false);
  }

  Future<void> _toggle(Map<String,dynamic> u,bool active)async{
    final username='${u['username']??''}';
    if(username.isEmpty||changing.contains(username))return;
    if(!active){
      final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
        title:const Text('Desligar usuário?'),
        content:Text('${u['fullName']??username} deixará de conseguir entrar no LUME e perderá a vaga ativa. Os dados de leitura permanecem guardados.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Desligar'))],
      ));
      if(ok!=true)return;
    }
    setState(()=>changing.add(username));
    try{
      await widget.services.api.setUserActive(username,active);
      await _load();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(active?'Usuário reativado.':'Usuário desligado. Uma vaga foi liberada.')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_message(e))));
    }finally{
      if(mounted)setState(()=>changing.remove(username));
    }
  }

  String _lastAccess(dynamic value){
    final ms=value is num?value.toInt():int.tryParse('$value');
    if(ms==null||ms<=0)return 'Nunca entrou';
    final d=DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int n)=>n.toString().padLeft(2,'0');
    return 'Último acesso ${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Usuários'),actions:[IconButton(onPressed:loading?null:(){setState(()=>loading=true);_load();},tooltip:'Atualizar',icon:const Icon(Icons.refresh))]),
    body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('Erro ao carregar usuários: $error'))):RefreshIndicator(
      onRefresh:_load,
      child:ListView(
        physics:const AlwaysScrollableScrollPhysics(),
        children:[
          Padding(
            padding:const EdgeInsets.all(16),
            child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('$activeCount de $maxUsers perfis ativos',style:Theme.of(context).textTheme.titleMedium),
              const SizedBox(height:6),
              Text('${maxUsers-activeCount} ${maxUsers-activeCount==1?'vaga disponível':'vagas disponíveis'}'),
            ]))),
          ),
          if(users.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Center(child:Text('Nenhum usuário cadastrado.'))),
          for(final u in users)Builder(builder:(context){
            final username='${u['username']??''}';
            final active=u['active']==true||u['active']==1;
            final admin=u['role']=='admin';
            final sessionActive=u['sessionActive']==true;
            return ListTile(
              leading:CircleAvatar(child:Icon(admin?Icons.admin_panel_settings:Icons.person_outline)),
              title:Text('${u['fullName']??username}'),
              subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('@$username · ${u['className']??(admin?'Administração':'Turma não informada')}'),
                Text('${active?'Ativo':'Desligado'} · ${sessionActive?'Sessão ativa':'Sem sessão ativa'} · ${_lastAccess(u['lastLoginAt'])}'),
              ]),
              isThreeLine:true,
              trailing:admin?const Tooltip(message:'A conta administrativa não pode ser desligada',child:Icon(Icons.lock_outline)):changing.contains(username)?const SizedBox(width:24,height:24,child:CircularProgressIndicator(strokeWidth:2)):Switch.adaptive(value:active,onChanged:(v)=>_toggle(u,v)),
            );
          }),
        ],
      ),
    ),
  );
}
