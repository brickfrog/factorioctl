# Factorioctl

Like `kubectl` but Factorio. Inspired by that blog post about going this for rollercoaster tycoon.

This project will be implemented in 2 parts:
1. A Factorio mod to run inside the game to support operations as needed (this may not be strictly required as we can maybe execute lua over rcon)
2. A Rust CLI that will support higher level operations.

An experiment this project will be doing that the rollercoaster tycoon one did not is experimenting with higher level abstractions for the tool.
The blog post calls out that the LLM got confused with pathing with the ASCII map interface. Rather than doing only that, we will also provide
a graph representation of things and provide algorithms like A* to allow the LLM to perform reasonable operations and checks without needing
to do all the work on their own. We can offload as much as possible to the tool allowing the LLM to focus on decision making.

There is an alias provided `factorio` to the factorio binary here.

Factorio is installed at `/Users/mark/Library/Application Support/Steam/steamapps/common/Factorio`. It may be necessary to look into some of these files.
i.e. the `--help` text just refers to lua files for settings for map generation.

This project will be divided into a few phases:
1. Initial testing. Create mini tools to do things like generate a map with no enemies that we can test on. Create the simplest possible e2e test. Get data from a factorio world, place an object down or mine something or do any interaction at all. Once we've validated that the core concepts can work at all we can move on.
2. High level design. Scope out the ideas for an initial end to end demo. Based on what we learned from the previous step, we should rescope the project and come up with a more complete design for something functional. We will then go through multiple rounds of review before getting started with the coding.
3. Implement the components as described above with focused test suites to prevent regressions and frequent git commits to organize work.
4. Once the tool works, we will design a test for Claude code to accomplish some goal or task in the game and then attempt it. Learning about how this works and collecting that data. Based on the results we can iterate and do more work.

The desired end goal is both a generally usable CLI tool for getting and setting state in factorio but also having an LLM play factorio.
