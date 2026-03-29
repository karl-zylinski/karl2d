PUT DESCRIPTION OF PULL REQUEST HERE

---

## Rules Checklist

You can always submit a draft pull request. But when you make your Pull Request "ready for review", then please make sure these rules are followed:
- [ ] Make sure that the code you submit is working and tested.
- [ ] Do not submit "basic" or "rudimentary" code that needs further work to actually be finished. Finish the code to the best of your abilities.
- [ ] Do not modify any code that is unrelated to your changes. That just makes reviewing your code harder: I'll have a hard time seeing what you actually did. Do not use auto formatters such as odinfmt.
- [ ] If you used an LLM to generate any code, then make that you understand every single line. In other words: No form of "vibe coded" PRs are allowed.
- [ ] If you commit changes that were unintended, just do additional commits that undo them. Don't worry about polluting the commit history: I will do a "squash merge" of your Pull Request. Just make sure that the diff in the "Files changed" tab looks tidy.
- [ ] The GitHub testing actions will make sure that the `karl2d.doc.odin` file is up-to-date. I enforce this because it will make you see if you changed any parts of the user-facing API. This way we find API-breaking changes before they are merged. Regenerate `karl2d.doc.odin` by running `odin run tools/api_doc_builder` in the root folder of the repository.
- [ ] Finally, about code style: Make sure that the code follows the same style as in `karl2d.odin`:
	- Please look through that file and pay attention to how characters such as `:` `=`, `(` `{` etc are placed.
	- Use tabs, not spaces.
	- Lines cannot be longer than 100 characters. See the `init` proc in `karl2d.odin` for an example of how to split up procedure signatures that are too long. That proc also shows how to write API comments. Use a _ruler_ in your editor to make it easy to spot long lines.
