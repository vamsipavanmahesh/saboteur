# Message style: warnings and notes

How saboteur's own messages are written. This is a contributor convention:
it applies to every warning and note the tool prints or records - anything
that goes through `Diagnostics#warn` (report warnings), `#inform` (stderr
notes) or `#announce` (both), or that the CLI prints to stderr. Progress
marks and usage errors are not warnings and keep their own formats.

A warning a user cannot act on in one read is noise. Field reports (#309,
#311, #312, #316) showed the same failure shape: a correct message that
buries what to do under why it happened, in one long line.

## The rules

1. **Lead with what the user can do.** When there is a remedy, the first
   clause is the remedy. When there is nothing to do, lead with the
   outcome instead ("nothing to test", "5 subject(s) skipped").
2. **One sentence of cause, then details on their own lines.** After the
   action, one sentence says why. Anything longer - paths, thread names,
   counts - goes on indented lines underneath, never into a longer
   sentence.
3. **Name at most five items.** More than five paths or names becomes the
   first five and "and N more".
4. **Never print secret values.** Environment variable contents, tokens
   and credentials stay out of messages; name the variable, not its value.

Keep the first line short enough to read in a narrow terminal; wrap the
rest instead of widening the line.

## Before and after

A note that ends with the remedy, from the boot-once warning:

```text
Billing::Invoice#total: covered by every test and run at boot - mutants apply after boot, so a survivor can be a boot-once effect the suite cannot re-observe (#575); verify it by mutating the file on disk
```

The same note led by the action:

```text
Billing::Invoice#total: verify a survivor here by mutating the file on disk
  covered by every test and run at boot: mutants apply after boot, so a survivor can be a boot-once effect the suite cannot re-observe (#575)
```

The five-item rule:

```text
# before
7 pattern(s) matched nothing: spec/a_spec.rb, spec/b_spec.rb, spec/c_spec.rb, spec/d_spec.rb, spec/e_spec.rb, spec/f_spec.rb, spec/g_spec.rb
# after
7 pattern(s) matched nothing: spec/a_spec.rb, spec/b_spec.rb, spec/c_spec.rb, spec/d_spec.rb, spec/e_spec.rb, and 2 more
```

## Applying it

Rewrites keep every diagnostic detail the old message carried - the
convention reorders and wraps, it does not drop information a spec or a
doc relies on. Specs pin the first clause of each rewritten message, so
the action stays first. When a message gains a sibling (a new warn site),
write it in this shape from the start.
