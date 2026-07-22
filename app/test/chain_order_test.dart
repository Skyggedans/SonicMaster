import 'package:flutter_test/flutter_test.dart';
import 'package:sonicmaster/model/chain_order.dart';

void main() {
  const u01 = ['NR', 'FX1', 'DRV', 'AMP', 'IR', 'EQ', 'FX2', 'DLY', 'RVB'];

  test('collapseChain groups the amp block and keeps 6 groups', () {
    final groups = collapseChain(u01);

    expect(groups.length, 6);
    expect(groups.where(isAmpBlock).length, 1);
    expect(groups.firstWhere(isAmpBlock), ampBlock);
    // free modules are singletons
    expect(groups.where((g) => g.length == 1).length, 5);
  });

  test('flattenChain is the inverse of collapseChain', () {
    expect(flattenChain(collapseChain(u01)), u01);
  });

  test('reordering groups keeps the amp block contiguous & ordered', () {
    final groups = collapseChain(u01);
    // rotate left by one
    final rotated = [...groups.sublist(1), groups.first];
    final flat = flattenChain(rotated);
    // block still contiguous, exact order
    final i = flat.indexOf('DRV');

    expect(flat.sublist(i, i + 4), ampBlock);
    expect(chainKey(rotated), flat.join('-'));
  });

  test('collapseChain leaves a split/misordered block as singletons', () {
    // AMP before DRV -> not the block; all singletons (9 groups)
    const weird = ['AMP', 'DRV', 'IR', 'EQ', 'NR', 'FX1', 'FX2', 'DLY', 'RVB'];
    final groups = collapseChain(weird);

    expect(groups.where(isAmpBlock).length, 0);
    expect(flattenChain(groups), weird);
  });
}
