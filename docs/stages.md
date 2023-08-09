## Stages

Stages are groups of systems that can be invoked together.

You can create your own, but there are 7 default stages:

+ `init` - Run when `World.init` is called. Used for initializing resources, and anything that _has_ to be done first.
+ `load` - Used for loading assets, and using the initialized resources
+ `pre_update`
+ `update`
+ `post_update`
+ `draw`
+ `deinit` - `Run when World.deinit` is called. Used for deinitializing resources and assets

By default, zentig doesn't add any systems to any of your stages. So you can use any
of these systems for whatever purpose you want.

### Stage layout

Stages have labels within them to help you order your systems,
by default each stage has a `body` label.

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

With each label and section within those labels being run in order.

See more about system ordering [here](https://github.com/freakmangd/zentig_ecs/tree/main/docs/system_ordering.md).

### Adding stages

Adding stages is done through the `WorldBuilder`:

```zig
wb.addStage(.my_stage);
wb.addSystemsToStage(.my_stage, mySystem);

// ...

world.runStage(.my_stage);
```
