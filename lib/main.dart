import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_auth/firebase_auth.dart';

const clinicName = 'Studio Dott. Arzilli';
const clinicPhone = '0765 876646';
const clinicAddress =
    'Viale Umberto I, 66\n'
    '02037 Poggio Moiano RI';

const primaryBlue = Color(0xFF1769C2);
const darkBlue = Color(0xFF0B376F);
const backgroundColor = Color(0xFFF8FAFD);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  usePathUrlStrategy();
  runApp(const NumerettiDottoreApp());
}

class QueueController extends ChangeNotifier {
  int currentNumber = 0;
  DateTime? calledAt;

  final DatabaseReference _queueReference =
      FirebaseDatabase.instance.ref('queue');

  QueueController() {
    _listenToQueue();
  }

  void _listenToQueue() {
    _queueReference.onValue.listen(
      (DatabaseEvent event) {
        final Object? value = event.snapshot.value;

        if (value is Map) {
          final Map<Object?, Object?> data = value;

          final Object? numberValue = data['currentNumber'];
          final Object? calledAtValue = data['calledAt'];

          currentNumber =
              numberValue is num ? numberValue.toInt() : 0;

          calledAt = calledAtValue is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  calledAtValue.toInt(),
                )
              : null;
        } else {
          currentNumber = 0;
          calledAt = null;
        }

        notifyListeners();
      },
      onError: (Object error) {
        debugPrint(
          'Errore durante la lettura della coda: $error',
        );
      },
    );
  }

  Future<void> nextNumber() async {
    await _queueReference.runTransaction((Object? value) {
      final Map<String, dynamic> data = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};

      final Object? oldNumber = data['currentNumber'];
      final int number =
          oldNumber is num ? oldNumber.toInt() : 0;

      data['currentNumber'] = number + 1;
      data['calledAt'] = ServerValue.timestamp;

      return Transaction.success(data);
    });
  }

  Future<void> previousNumber() async {
    await _queueReference.runTransaction((Object? value) {
      final Map<String, dynamic> data = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};

      final Object? oldNumber = data['currentNumber'];
      final int number =
          oldNumber is num ? oldNumber.toInt() : 0;

      data['currentNumber'] = number > 0 ? number - 1 : 0;
      data['calledAt'] = ServerValue.timestamp;

      return Transaction.success(data);
    });
  }

  Future<void> resetNumber() async {
    await _queueReference.update({
      'currentNumber': 0,
      'calledAt': null,
    });
  }
}

class NumerettiDottoreApp extends StatefulWidget {
  const NumerettiDottoreApp({super.key});

  @override
  State<NumerettiDottoreApp> createState() =>
      _NumerettiDottoreAppState();
}

class _NumerettiDottoreAppState extends 
State<NumerettiDottoreApp> {
  final QueueController queueController = QueueController();

  @override
  void dispose() {
    queueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: clinicName,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
        ),
        scaffoldBackgroundColor: backgroundColor,
      ),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/dottore':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => DoctorPage(
                controller: queueController,
              ),
            );

          case '/':
          default:
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => PatientPage(
                controller: queueController,
              ),
            );
        }
      },
    );
  }
}

class PatientPage extends StatelessWidget {
  const PatientPage({
    required this.controller,
    super.key,
  });

  final QueueController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return ClinicLayout(
          currentNumber: controller.currentNumber,
          calledAt: controller.calledAt,
          showDoctorControls: false,
        );
      },
    );
  }
}

class DoctorPage extends StatelessWidget {
  const DoctorPage({
    required this.controller,
    super.key,
  });

  final QueueController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData) {
          return DoctorDashboard(
            controller: controller,
          );
        }

        return const DoctorLoginPage();
      },
    );
  }
}

class DoctorLoginPage extends StatefulWidget {
  const DoctorLoginPage({super.key});

  @override
  State<DoctorLoginPage> createState() => _DoctorLoginPageState();
}

class _DoctorLoginPageState extends State<DoctorLoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool hidePassword = true;
  String? errorMessage;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Inserisci email e password.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      String message;

      switch (error.code) {
        case 'invalid-email':
          message = 'L’indirizzo email non è valido.';
          break;

        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
          message = 'Email o password non corrette.';
          break;

        case 'user-disabled':
          message = 'Questo account è stato disabilitato.';
          break;

        case 'too-many-requests':
          message =
              'Troppi tentativi. Attendi qualche minuto e riprova.';
          break;

        default:
          message = 'Accesso non riuscito. Riprova.';
      }

      if (mounted) {
        setState(() {
          errorMessage = message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          errorMessage = 'Si è verificato un errore imprevisto.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                maxWidth: 450,
              ),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: darkBlue.withValues(alpha: 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const ClinicLogo(
                    compact: false,
                  ),

                  const SizedBox(height: 22),

                  const Text(
                    'ACCESSO MEDICO',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: darkBlue,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    clinicName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      color: primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 30),

                  TextField(
                    controller: emailController,
                    enabled: !isLoading,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(
                        Icons.email_rounded,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  TextField(
                    controller: passwordController,
                    enabled: !isLoading,
                    obscureText: hidePassword,
                    autofillHints: const [
                      AutofillHints.password,
                    ],
                    onSubmitted: (_) {
                      if (!isLoading) {
                        login();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(
                        Icons.lock_rounded,
                      ),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            hidePassword = !hidePassword;
                          });
                        },
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),

                  if (errorMessage != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 26),

                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      onPressed: isLoading ? null : login,
                      icon: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.login_rounded,
                            ),
                      label: Text(
                        isLoading
                            ? 'ACCESSO IN CORSO...'
                            : 'ACCEDI',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DoctorDashboard extends StatelessWidget {
  const DoctorDashboard({
    required this.controller,
    super.key,
  });

  final QueueController controller;

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Stack(
          children: [
            ClinicLayout(
              currentNumber: controller.currentNumber,
              calledAt: controller.calledAt,
              showDoctorControls: true,
              onPrevious: () {
                controller.previousNumber();
              },
              onNext: () {
                controller.nextNumber();
              },
              onReset: () {
                controller.resetNumber();
              },
            ),
            Positioned(
              top: 18,
              right: 18,
              child: SafeArea(
                child: OutlinedButton.icon(
                  onPressed: logout,
                  icon: const Icon(
                    Icons.logout_rounded,
                  ),
                  label: const Text('ESCI'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: darkBlue,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ClinicLayout extends StatelessWidget {
    const ClinicLayout({
      required this.currentNumber,
      required this.calledAt,
      required this.showDoctorControls,
    this.onPrevious,
    this.onNext,
    this.onReset,
    super.key,
  });

  final int currentNumber;
  final DateTime? calledAt;
  final bool showDoctorControls;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(
              color: backgroundColor,
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BottomWaves(),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 750;

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            constraints.maxWidth > 700 ? 40 : 22,
                        vertical: compact ? 16 : 24,
                      ),
                      child: Column(
                        children: [
                          ClinicLogo(compact: compact),

                          SizedBox(height: compact ? 12 : 18),

                          Text(
                            clinicName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: compact ? 34 : 48,
                              fontWeight: FontWeight.w800,
                              color: darkBlue,
                              letterSpacing: -1,
                            ),
                          ),

                          SizedBox(height: compact ? 18 : 30),

                          const DecorativeDivider(),

                          SizedBox(height: compact ? 18 : 28),

                          Text(
                            'NUMERO',
                            style: TextStyle(
                              fontSize: compact ? 30 : 38,
                              fontWeight: FontWeight.w800,
                              color: primaryBlue,
                              letterSpacing: 6,
                            ),
                          ),

                          SizedBox(height: compact ? 4 : 8),

                          Text(
                            '$currentNumber',
                            style: TextStyle(
                              fontSize: compact ? 120 : 170,
                              height: 0.95,
                              fontWeight: FontWeight.w800,
                              color: darkBlue,
                            ),
                          ),

                          if (currentNumber > 0 && calledAt != null) ...[
                            SizedBox(height: compact ? 4 : 6),
                            Text(
                              '${calledAt!.hour.toString().padLeft(2, '0')}:'
                              '${calledAt!.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: compact ? 11 : 13,
                                fontWeight: FontWeight.w300,
                                color: const Color(0xFF90A4AE),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],

                          if (showDoctorControls) ...[
                            SizedBox(height: compact ? 22 : 32),

                            DoctorControls(
                              currentNumber: currentNumber,
                              onPrevious: onPrevious!,
                              onNext: onNext!,
                              onReset: onReset!,
                            ),
                          ] else
                            SizedBox(height: compact ? 25 : 45),

                          SizedBox(height: compact ? 28 : 42),

                          InformationCard(compact: compact),

                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DoctorControls extends StatelessWidget {
  const DoctorControls({
    required this.currentNumber,
    required this.onPrevious,
    required this.onNext,
    required this.onReset,
    super.key,
  });

  final int currentNumber;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: 145,
              height: 60,
              child: OutlinedButton.icon(
                onPressed: currentNumber > 0 ? onPrevious : null,
                icon: const Icon(Icons.fast_rewind_rounded),
                label: const Text('INDIETRO'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryBlue,
                  backgroundColor: Colors.white,
                  side: const BorderSide(
                    color: primaryBlue,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            Container(
              width: 145,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: primaryBlue.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.fast_forward_rounded),
                label: const Text('AVANTI'),
                style: FilledButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        SizedBox(
          width: 200,
          height: 52,
          child: TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('AZZERA'),
            style: TextButton.styleFrom(
              foregroundColor: darkBlue,
            ),
          ),
        ),
      ],
    );
  }
}

class ClinicLogo extends StatelessWidget {
  const ClinicLogo({
    required this.compact,
    super.key,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 68.0 : 86.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: primaryBlue,
          width: 4,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(
        Icons.monitor_heart_rounded,
        size: 44,
        color: primaryBlue,
      ),
    );
  }
}

class DecorativeDivider extends StatelessWidget {
  const DecorativeDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 85,
          height: 2,
          color: primaryBlue.withValues(alpha: 0.25),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: primaryBlue,
          ),
        ),
        Container(
          width: 85,
          height: 2,
          color: primaryBlue.withValues(alpha: 0.25),
        ),
      ],
    );
  }
}

class InformationCard extends StatelessWidget {
  const InformationCard({
    required this.compact,
    super.key,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        maxWidth: 650,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 22 : 32,
        vertical: compact ? 20 : 26,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: primaryBlue.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: darkBlue.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Column(
        children: [
          Text(
            'INFORMAZIONI',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: primaryBlue,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: 20),
          InformationRow(
            icon: Icons.location_on_rounded,
            text: clinicAddress,
          ),
          SizedBox(height: 18),
          InformationRow(
            icon: Icons.phone_rounded,
            text: clinicPhone,
          ),
        ],
      ),
    );
  }
}

class InformationRow extends StatelessWidget {
  const InformationRow({
    required this.icon,
    required this.text,
    super.key,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryBlue.withValues(alpha: 0.10),
            ),
            child: Icon(
              icon,
              color: primaryBlue,
              size: 28,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 18,
                height: 1.35,
                color: darkBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BottomWaves extends StatelessWidget {
  const BottomWaves({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      width: double.infinity,
      child: CustomPaint(
        painter: WavePainter(),
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final lightWave = Paint()
      ..color = const Color(0xFF82B6F4)
      ..style = PaintingStyle.fill;

    final darkWave = Paint()
      ..color = primaryBlue
      ..style = PaintingStyle.fill;

    final lightPath = Path()
      ..moveTo(0, 42)
      ..quadraticBezierTo(
        size.width * 0.35,
        105,
        size.width * 0.7,
        50,
      )
      ..quadraticBezierTo(
        size.width * 0.88,
        20,
        size.width,
        34,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(lightPath, lightWave);

    final darkPath = Path()
      ..moveTo(0, 62)
      ..quadraticBezierTo(
        size.width * 0.35,
        125,
        size.width * 0.72,
        76,
      )
      ..quadraticBezierTo(
        size.width * 0.9,
        52,
        size.width,
        58,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(darkPath, darkWave);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}