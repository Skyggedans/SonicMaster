/// Pure helpers for the pedal's signal-chain reorder model.
///
/// Reorder space = 6 draggable groups: the 5 free modules
/// (NR, FX1, FX2, DLY, RVB) plus one fixed contiguous block
/// [DRV, AMP, IR, EQ] whose internal order never changes.
library;

/// The amp block: these four modules always move together, in this exact order.
const List<String> ampBlock = ['DRV', 'AMP', 'IR', 'EQ'];

/// True iff [group] is exactly the amp block.
bool isAmpBlock(List<String> group) =>
    group.length == ampBlock.length &&
    ampBlock.indexed.every((e) => group[e.$1] == e.$2);

/// Collapses a flat 9-name signal order into draggable groups: the amp block
/// (when its four names are contiguous and in order) becomes one 4-element
/// group; every other module becomes a singleton group.
List<List<String>> collapseChain(List<String> order) {
  final groups = <List<String>>[];
  var i = 0;

  // Variable-step cursor: advances by the whole block on a match, else by one.
  while (i < order.length) {
    if (i + ampBlock.length <= order.length &&
        order[i] == ampBlock[0] &&
        order[i + 1] == ampBlock[1] &&
        order[i + 2] == ampBlock[2] &&
        order[i + 3] == ampBlock[3]) {
      groups.add(List<String>.from(ampBlock));
      i += ampBlock.length;
    } else {
      groups.add([order[i]]);
      i++;
    }
  }

  return groups;
}

/// Concatenates groups back into the flat name list.
List<String> flattenChain(List<List<String>> groups) => [
  for (final g in groups) ...g,
];

/// The `chainOrderCommands` table key for the given group arrangement.
String chainKey(List<List<String>> groups) => flattenChain(groups).join('-');
