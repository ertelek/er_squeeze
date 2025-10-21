import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutTab extends StatefulWidget {
  const AboutTab({super.key});
  @override
  State<AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<AboutTab> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _version = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      setState(() => _version = 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    const appName = 'Squeeze!';
    const description = 'Compress videos on your phone to save space.';

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appName,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(description),
                    const SizedBox(height: 8),
                    Text('Version: $_version',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Licenses'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              LicenseCard(
                title: 'This app ($appName)',
                subtitle: 'GNU General Public License v3.0 (GPL-3.0)',
                notice: '''
This application is licensed under the GNU General Public License version 3 (GPLv3).
You are free to run, study, share, and modify the software under the terms of the GPLv3.
A copy of the GPLv3 license text should be provided with the distribution.
For details, see https://github.com/ertelek/squeeze/blob/main/LICENSE
''',
                url: 'https://github.com/ertelek/squeeze/blob/main/LICENSE',
              ),
              LicenseCard(
                title: 'FFmpeg Kit (ffmpeg_kit_flutter_new)',
                subtitle: 'GNU General Public License v3.0 (GPL-3.0)',
                notice: '''
FFmpeg Kit (and the FFmpeg binaries it bundles in the GPL variant) are licensed under GPLv3 (and/or other compatible licenses for included libraries).
Source code and license details are available from the FFmpeg Kit project and FFmpeg upstream.
See https://github.com/sk3llo/ffmpeg_kit_flutter/blob/master/LICENSE
''',
                url: 'https://github.com/sk3llo/ffmpeg_kit_flutter/blob/master/LICENSE',
              ),
              LicenseCard(
                title: 'FFmpeg',
                subtitle:
                    'GNU Lesser General Public License (LGPL) v2.1 or later (GPL may apply if enabled components require it)',
                notice: '''
FFmpeg is licensed under the GNU Lesser General Public License (LGPL) version 2.1 or later.
However, FFmpeg incorporates several optional parts and optimizations that are covered by the GNU General Public License (GPL) version 2 or later.
If those parts get used the GPL applies to all of FFmpeg.
See https://www.ffmpeg.org/legal.html for the full text.
''',
                url: 'https://www.ffmpeg.org/legal.html',
              ),
              LicenseCard(
                title: 'x264',
                subtitle: 'GNU General Public License v2 or later (GPL-2.0+)',
                notice: '''
x264 is free software licensed under the GNU GPL version 2 (or, at your option, any later version).
See https://x264.org/licensing/ and the included COPYING file for the full text.
''',
                url: 'https://x264.org/licensing/',
              ),
              LicenseCard(
                title: 'Other Dart/Flutter packages',
                subtitle: 'Various open-source licenses',
                notice: '''
This app uses additional Dart/Flutter packages which include their own licenses.
You can view those licenses via the license screen below.
''',
                onTapOverride: () {
                  showLicensePage(
                    context: context,
                    applicationName: appName,
                    applicationVersion: _version,
                    applicationLegalese:
                        '© ${DateTime.now().year} The $appName contributors',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              showLicensePage(
                context: context,
                applicationName: appName,
                applicationVersion: _version,
                applicationLegalese:
                    '© ${DateTime.now().year} The $appName contributors',
              );
            },
            icon: const Icon(Icons.article_outlined),
            label: const Text('View Dart/Flutter package licenses'),
          ),
        ],
      ),
    );
  }
}

class LicenseCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String notice;
  final String? url;
  final VoidCallback? onTapOverride;

  const LicenseCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.notice,
    this.url,
    this.onTapOverride,
  });

  Future<void> _openUrl(BuildContext context) async {
    if (onTapOverride != null) {
      onTapOverride!();
      return;
    }
    if (url == null || url!.isEmpty) return;

    final uri = Uri.tryParse(url!);
    if (uri == null) return;

    if (!await canLaunchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
      return;
    }
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openUrl(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54)),
              const SizedBox(height: 8),
              Text(
                notice.trim(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (url != null && url!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.open_in_new, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        url!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              decoration: TextDecoration.underline,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
