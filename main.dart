import 'package:flutter/material.dart';

void main() => runApp(const DoseCropCalcApp());

class DoseCropCalcApp extends StatelessWidget {
  const DoseCropCalcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DoseCropCalc',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      home: const DoseCropCalculatorScreen(),
    );
  }
}

// Phase 数据结构
class Phase {
  String name;
  List<PTVEntry> ptvs;

  Phase(this.name, this.ptvs);
}

class PTVEntry {
  String name;
  int dose;

  PTVEntry(this.name, this.dose);
}

class DoseCropCalculatorScreen extends StatefulWidget {
  const DoseCropCalculatorScreen({super.key});

  @override
  State<DoseCropCalculatorScreen> createState() =>
      _DoseCropCalculatorScreenState();
}

class _DoseCropCalculatorScreenState
    extends State<DoseCropCalculatorScreen> {
  // OAR 全局参数（所有 Phase 共享）
  String _oarName = 'BowelBag';
  bool _isLargeOAR = false;
  int _oarConstraint = 5400;

  // 多 Phase 列表
  List<Phase> _phases = [
    Phase('Phase 1', [
      PTVEntry('PTV_High', 7000),
      PTVEntry('PTV_Int', 6300),
      PTVEntry('PTV_Low', 5040),
    ]),
  ];

  // 计算结果
  List<Map<String, dynamic>> _ptvCropTable = [];
  Map<String, List<Map<String, dynamic>>> _sibTables = {};
  String _summary = '';

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  void _addPhase() {
    final phaseNum = _phases.length + 1;
    setState(() {
      _phases.add(Phase(
        'Phase $phaseNum',
        [
          PTVEntry('PTV_High', 7000),
          PTVEntry('PTV_Int', 6300),
        ],
      ));
    });
  }

  void _removePhase(int index) {
    if (_phases.length > 1) {
      setState(() {
        _phases.removeAt(index);
      });
    }
  }

  void _addPTVToPhase(int phaseIndex) {
    setState(() {
      _phases[phaseIndex].ptvs.add(PTVEntry('PTV_${_phases[phaseIndex].ptvs.length + 1}', 5000));
    });
  }

  void _removePTV(int phaseIndex, int ptvIndex) {
    if (_phases[phaseIndex].ptvs.length > 1) {
      setState(() {
        _phases[phaseIndex].ptvs.removeAt(ptvIndex);
      });
    }
  }

  void _calculate() {
    // 1. 计算 PTV 裁剪距离（跨 Phase 合并所有 PTV）
    final allPtvs = <PTVEntry>[];
    for (final phase in _phases) {
      allPtvs.addAll(phase.ptvs);
    }

    final ptvCropTable = <Map<String, dynamic>>[];
    final ptvNames = allPtvs.map((e) => e.name).toList().toSet().toList(); // 去重

    for (final ptv in allPtvs) {
      final row = <String, dynamic>{'PTV': ptv.name};
      for (final targetPtvName in ptvNames) {
        if (ptv.name == targetPtvName) {
          row[targetPtvName] = 'N/A';
        } else {
          final targetPtv = allPtvs.firstWhere((p) => p.name == targetPtvName, orElse: () => allPtvs[0]);
          // 简化规则：高剂量 → 低剂量 有距离，反之无
          if (ptv.dose > targetPtv.dose) {
            // 示例：固定值（实际可查表）
            if (ptv.name == 'PTV_High' && targetPtvName == 'PTV_Int') {
              row[targetPtvName] = 0.20;
            } else if (ptv.name == 'PTV_High' && targetPtvName == 'PTV_Low') {
              row[targetPtvName] = 0.56;
            } else if (ptv.name == 'PTV_Int' && targetPtvName == 'PTV_Low') {
              row[targetPtvName] = 0.40;
            } else {
              row[targetPtvName] = '--';
            }
          } else {
            row[targetPtvName] = '--';
          }
        }
      }

      // OAR 距离（使用当前 PTV 的剂量）
      final ptvDose = ptv.dose;
      double oarDistance;
      if (_isLargeOAR) {
        if (_oarConstraint > ptvDose * 0.75) {
          oarDistance = 0.46;
        } else {
          oarDistance = 0.29;
        }
      } else {
        oarDistance = 0.33;
      }
      row['OAR'] = oarDistance;
      row['Constraint'] = _oarConstraint;
      ptvCropTable.add(row);
    }

    // 2. 计算 SIB Rings（每个 Phase 独立计算）
    final sibTables = <String, List<Map<String, dynamic>>>{};
    for (final phase in _phases) {
      // 按剂量降序排序 PTV
      final sortedPtvs = List<PTVEntry>.from(phase.ptvs)
        ..sort((a, b) => b.dose.compareTo(a.dose));

      final sibRows = <Map<String, dynamic>>[];
      final ringDistances = <double>[]; // SIB_1, SIB_2...

      // 计算 SIB 环（从最高剂量向外）
      for (int i = 0; i < sortedPtvs.length - 1; i++) {
        final dose1 = sortedPtvs[i].dose;
        final dose2 = sortedPtvs[i + 1].dose;
        // 5%/mm = 500 cGy/cm
        final distance = (dose1 - dose2) / 500.0;
        ringDistances.add(distance);
      }

      // 填充表格：每一行对应一个 PTV
      for (int i = 0; i < sortedPtvs.length; i++) {
        final row = <String, dynamic>{'PTV': sortedPtvs[i].name};
        for (int j = 0; j < ringDistances.length; j++) {
          // SIB_{j+1} 距离 = 前 j 个环距离之和
          double totalDist = 0;
          for (int k = 0; k <= j; k++) {
            if (k < ringDistances.length) {
              totalDist += ringDistances[k];
            }
          }
          row['SIB_${j + 1}'] = totalDist;
        }
        sibRows.add(row);
      }

      sibTables[phase.name] = sibRows;
    }

    // 3. 摘要
    final summary = '''
📌 剂量跌落规则摘要:
1. PTV_High → PTV_Int → PTV_Low: 5%/mm
2. 小体积 OAR: 10%/mm → 裁剪距离 ≈ 0.33 cm
3. 大体积 OAR:
   - 约束 >75% PTV 剂量 → 5%/mm → ≈0.46 cm
   - 约束 <75% PTV 剂量 → 3%/mm → ≈0.29 cm
4. SIB 环: 使用 5%/mm (500 cGy/cm) 计算
   - 距离 (cm) = (D1 - D2) / 500
''';

    setState(() {
      _ptvCropTable = ptvCropTable;
      _sibTables = sibTables;
      _summary = summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DoseCropCalc - 多相版'),
        backgroundColor: Colors.blue[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: () {
              setState(() {
                _phases = [
                  Phase('Phase 1', [
                    PTVEntry('PTV_High', 7000),
                    PTVEntry('PTV_Int', 6300),
                    PTVEntry('PTV_Low', 5040),
                  ]),
                ];
                _oarName = 'BowelBag';
                _isLargeOAR = false;
                _oarConstraint = 5400;
              });
              _calculate();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // OAR 全局设置
            const Text('OAR 设置（所有 Phase 共享）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextField(
              decoration: const InputDecoration(
                labelText: 'OAR 器官名称',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _oarName),
              onChanged: (value) => setState(() => _oarName = value),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('体积: ', style: TextStyle(fontSize: 16)),
                RadioListTile<bool>(
                  title: const Text('小'),
                  value: false,
                  groupValue: _isLargeOAR,
                  onChanged: (value) => setState(() {
                    _isLargeOAR = value!;
                    _calculate();
                  }),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<bool>(
                  title: const Text('大'),
                  value: true,
                  groupValue: _isLargeOAR,
                  onChanged: (value) => setState(() {
                    _isLargeOAR = value!;
                    _calculate();
                  }),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'OAR 最大剂量约束 (cGy)',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: '$_oarConstraint'),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                if (value.isNotEmpty) {
                  setState(() {
                    _oarConstraint = int.tryParse(value) ?? 0;
                  });
                  _calculate();
                }
              },
            ),
            const SizedBox(height: 20),

            // Phase 列表
            const Text('治疗相 (Phases)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ..._phases.asMap().entries.map((phaseEntry) {
              final phaseIndex = phaseEntry.key;
              final phase = phaseEntry.value;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('🔹 ${phase.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          if (_phases.length > 1)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removePhase(phaseIndex),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...phase.ptvs.asMap().entries.map((ptvEntry) {
                        final ptvIndex = ptvEntry.key;
                        final ptv = ptvEntry.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(labelText: 'PTV 名称'),
                                  controller: TextEditingController(text: ptv.name),
                                  onChanged: (value) => setState(() {
                                    _phases[phaseIndex].ptvs[ptvIndex].name = value;
                                    _calculate();
                                  }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(labelText: '剂量 (cGy)'),
                                  controller: TextEditingController(text: '${ptv.dose}'),
                                  keyboardType: TextInputType.number,
                                  onChanged: (value) {
                                    final dose = int.tryParse(value) ?? 0;
                                    setState(() {
                                      _phases[phaseIndex].ptvs[ptvIndex].dose = dose;
                                    });
                                    _calculate();
                                  },
                                ),
                              ),
                              if (phase.ptvs.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle, color: Colors.orange),
                                  onPressed: () => _removePTV(phaseIndex, ptvIndex),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 8),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () => _addPTVToPhase(phaseIndex),
                          icon: const Icon(Icons.add),
                          label: const Text('添加 PTV 到此 Phase'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[300],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),

            Center(
              child: ElevatedButton.icon(
                onPressed: _addPhase,
                icon: const Icon(Icons.add_circle, color: Colors.white),
                label: const Text('添加新 Phase'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 计算按钮
            Center(
              child: ElevatedButton(
                onPressed: _calculate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple[700],
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                ),
                child: const Text('重新计算', style: TextStyle(fontSize: 18)),
              ),
            ),

            const SizedBox(height: 20),

            // 结果：PTV 裁剪距离
            if (_ptvCropTable.isNotEmpty) ...[
              const Text('📊 z_opt_PTV 裁剪距离 (cm)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              _buildDataTable(
                columns: [
                  'PTV',
                  ..._ptvCropTable.expand((row) => row.keys.where((k) => k != 'PTV' && k != 'OAR' && k != 'Constraint')).toSet().toList(),
                  'OAR',
                  'Constraint',
                ],
                rows: _ptvCropTable,
              ),
              const SizedBox(height: 20),
            ],

            // 结果：SIB Rings（每个 Phase 一个表）
            ..._sibTables.entries.map((entry) {
              final phaseName = entry.key;
              final sibRows = entry.value;
              if (sibRows.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🌀 $phaseName: SIB Ring 裁剪距离 (cm)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  _buildSibTable(sibRows),
                  const SizedBox(height: 20),
                ],
              );
            }).toList(),

            // 摘要
            if (_summary.isNotEmpty) ...[
              const Text('📘 剂量跌落规则', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(_summary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable({required List<String> columns, required List<Map<String, dynamic>> rows}) {
    return DataTable(
      columns: columns.map((col) => DataColumn(label: Text(col))).toList(),
      rows: rows.map((row) {
        return DataRow(
          cells: columns.map((col) {
            final value = row[col] ?? '--';
            return DataCell(Text(value.toString().toStringAsFixedIfDouble()));
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _buildSibTable(List<Map<String, dynamic>> rows) {
    final sibCols = rows.expand((row) => row.keys.where((k) => k.startsWith('SIB_'))).toSet().toList()
      ..sort();
    final columns = ['PTV', ...sibCols];

    return DataTable(
      columns: columns.map((col) => DataColumn(label: Text(col))).toList(),
      rows: rows.map((row) {
        return DataRow(
          cells: columns.map((col) {
            final value = row[col] ?? 0.0;
            if (value is double) {
              return DataCell(Text(value.toStringAsFixed(2)));
            }
            return DataCell(Text(value.toString()));
          }).toList(),
        );
      }).toList(),
    );
  }
}

extension DoubleFormat on String {
  String toStringAsFixedIfDouble() {
    if (this == 'N/A' || this == '--') return this;
    try {
      final d = double.parse(this);
      return d.toStringAsFixed(2);
    } catch (e) {
      return this;
    }
  }
}