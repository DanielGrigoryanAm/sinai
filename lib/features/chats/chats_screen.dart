import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  DateTime? _lastBackPressedAt;

  void _handleExitBack() {
    final now = DateTime.now();
    final shouldExit = _lastBackPressedAt != null &&
        now.difference(_lastBackPressedAt!) <= const Duration(seconds: 2);

    if (shouldExit) {
      SystemNavigator.pop();
      return;
    }

    _lastBackPressedAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Tap again to exit the app.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatBloc()..add(const GetChatsEvent()),
      child: BlocListener<ChatBloc, ChatState>(
        listener: (context, state) {
          if (state is ChatError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
          if (state is ChatDeleted) {
            context.read<ChatBloc>().add(const GetChatsEvent());
          }
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              _handleExitBack();
            }
          },
          child: Scaffold(
            appBar: CustomAppBar(
              title: 'Chats',
            ),
            backgroundColor: context.colorTheme.backgroundPrimary,
            body: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state is ChatLoading || state is ChatInitial) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is ChatsLoaded) {
                  if (state.chatCodes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 30,
                        children: [
                          Text('No chats yet'),
                          GestureDetector(
                            onTap: () => context
                                .read<ChatBloc>()
                                .add(const GetChatsEvent()),
                            child: Text(
                              'Refresh',
                              style: context.textTheme.hintText,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      context.read<ChatBloc>().add(const GetChatsEvent());
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: state.chatCodes.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final code = state.chatCodes[index];
                          const itemRadius =
                              BorderRadius.all(Radius.circular(14));
                          return Container(
                            decoration: BoxDecoration(
                              color: context.colorTheme.backgroundSecondary,
                              borderRadius: itemRadius,
                              border: Border.all(
                                color: context.colorTheme.border,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: itemRadius,
                              child: Slidable(
                                key: ValueKey(code),
                                endActionPane: ActionPane(
                                  motion: const ScrollMotion(),
                                  extentRatio: 0.18,
                                  children: [
                                    SlidableAction(
                                      onPressed: (_) {
                                        context
                                            .read<ChatBloc>()
                                            .add(DeleteChatEvent(code));
                                      },
                                      backgroundColor: Colors.red,
                                      icon: Icons.delete,
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: itemRadius,
                                  ),
                                  title: Text(code),
                                  onTap: () => context.router.push(
                                    ChatRoute(chatCode: code),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => context.router.push(const StartChatRoute()),
              backgroundColor: context.colorTheme.secondary,
              child:
                  Icon(Icons.add, color: context.colorTheme.backgroundPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
