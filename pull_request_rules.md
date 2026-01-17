Thank you for wanting to help with Karl2D development! These rules are for opening a _non-draft Pull Request_. You can always open a draft Pull Request and later make sure that it follows these rules.

1. Make sure that the code you submit is working and tested.
2. Do not submit "basic" or "rudimentary" code that needs further work to actually be finished. Finish the code to the best of your abilities.
3. Do not modify any code that is unrelated to your changes. That just makes reviewing your code harder: I'll havea hard time seeing what you actually did. Do not use auto-formatters such as odinfmt.
4. If you do make changes that were unintended, don't worry about polluting the commit history: I will do a "squash merge" of your Pull Request. Just make sure that the diff in the Changed Files tab looks tidy.
5. The GitHub testing actions will make sure that the [`karl2d.doc.odin`](https://github.com/karl-zylinski/karl2d/blob/master/karl2d.doc.odin) file is up-to-date. I enforce this because it will make you see if you changed any parts of the user-facing API. This way we find API-breaking changes before they are merged. Regenerate `karl2d.doc.odin` by running `odin run api_doc_builder`.
6. Finally, about code style: Make sure that the code follows the same style as in [`karl2d.odin`](https://github.com/karl-zylinski/karl2d/blob/master/karl2d.odin):
	- Please look through that file and pay attention to how characters such as `:` `=`, `(` `{` etc are placed.
	- Use tabs, not spaces.
	- Lines cannot be longer than 100 characters. See the `init` proc in [`karl2d.odin`](https://github.com/karl-zylinski/karl2d/blob/master/karl2d.odin) for an example of how to split up procedure signatures that are too long. That proc also shows how to write API comments. Use a _ruler_ in your editor to make it easy to spot long lines.