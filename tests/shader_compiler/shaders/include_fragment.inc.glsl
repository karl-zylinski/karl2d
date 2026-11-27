float include_fragment_only(float x) {
	return x + include_square(2.0) + abs(dFdx(x)) * 0.0;
}
