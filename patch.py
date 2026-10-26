m = open('memory.S').read()

# Replace adr with ldr =return_from_mapper at mem_write_4020_to_5FFF,
# adding a local .pool so the literal is reachable.
old = '''mem_write_4020_to_5FFF:
\tstr\tlr, [sp, #-4]!
\tadr\tlr, return_from_mapper
\tldr\tpc, [r9, #s_mapper_write_lo]'''

new = '''mem_write_4020_to_5FFF:
\tstr\tlr, [sp, #-4]!
\tldr\tlr, =return_from_mapper
\tldr\tpc, [r9, #s_mapper_write_lo]

\t.pool'''

assert old in m, "mem_write_4020_to_5FFF pattern not found"
m = m.replace(old, new, 1)
open('memory.S', 'w').write(m)
print("mem_write_4020_to_5FFF: adr -> ldr = with local pool")
print("Run: make clean && make")
