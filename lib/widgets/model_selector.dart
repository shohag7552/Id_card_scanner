import 'package:flutter/material.dart';
import '../services/gemini_nid_service.dart';
import '../theme/app_theme.dart';

/// A compact dropdown that lets the user choose which Gemini model runs the NID
/// scan. Backed by [GeminiNidService.availableModels]; the picked model id is
/// reported via [onChanged] so the parent can persist it / rebuild.
class ModelSelector extends StatelessWidget {
  final String selectedId;
  final ValueChanged<String> onChanged;

  const ModelSelector({
    super.key,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = GeminiNidService.availableModels.firstWhere(
      (m) => m.id == selectedId,
      orElse: () => GeminiNidService.availableModels.first,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderCol),
      ),
      child: Row(
        children: [
          const Icon(Icons.memory, color: AppTheme.secondary, size: 18),
          const SizedBox(width: 10),
          const Text(
            'AI Model',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected.id,
                isDense: true,
                isExpanded: true,
                dropdownColor: AppTheme.surfaceBg,
                borderRadius: BorderRadius.circular(12),
                alignment: AlignmentDirectional.centerEnd,
                icon: const Icon(Icons.expand_more, color: AppTheme.secondary),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                onChanged: (id) {
                  if (id != null) onChanged(id);
                },
                // Closed-button state: show ONLY the short label so it never
                // overflows the row.
                selectedItemBuilder: (context) => [
                  for (final m in GeminiNidService.availableModels)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        m.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
                // Open-menu state: label + wrapped description.
                items: [
                  for (final m in GeminiNidService.availableModels)
                    DropdownMenuItem<String>(
                      value: m.id,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            m.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
