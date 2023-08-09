## System Ordering
Systems can be ordered through labels, which are defineable points during the stages
that you can put your systems into.

### Stage Layout

Labels have 3 sections within them, a `.before`, `.during`, and `.after` section.

Every stage by default has a `.body` label, more can be added with `WorldBuilder.addLabel`.

You can think of stages like this:
```
Stage {
    body {
        before {},
        during {myUpdate},
        after {},
    },
    my_label {
        before {},
        during {},
        after {},
    },
}
```

Adding a stage using this syntax...
```zig
wb.addSystemsToStage(.update, myUpdate);
```

... adds it to the `.update` stage in the `.body` label in the `.during` section.

When a stage is run, it will go through each label in order and run the `before`, `during`,
and `after` section.

### Specifying sections and labels

You can specify the section and label with the `before()`, `during()`, and `after()` functions.

Example:
```zig
wb.addSystemsToStage(.update, ztg.after(.body, myUpdate));
```

This adds it to the `.update` stage in the `.body` label in the `.after` section.

### Creating custom labels

Labels can be created and ordered themselves.

```zig
wb.addLabel(.update, .my_label, .default); // This adds it to the end of the label list
wb.addLabel(.update, .my_after_label, .{ .after = .body });
wb.addLabel(.update, .my_before_label, .{ .before = .body });
```

### Example use case

The `GlobalTransform` component has a label in the `.post_update` stage called `.gtr_update`.

If you want to use the `GlobalTransform` component and have it be frame accurate, you will need
to put your system _after_ the `.gtr_update` label, like so:

```zig
wb.addSystemsToStage(.post_update, ztg.after(.gtr_update, myGtrSystem));
```
