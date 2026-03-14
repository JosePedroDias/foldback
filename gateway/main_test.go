package main

import (
	"testing"
	"github.com/stretchr/testify/assert"
)

func TestGameRegistry(t *testing.T) {
	names := gameNames()
	assert.Contains(t, names, "pong")
	assert.Contains(t, names, "bomberman")
	assert.Contains(t, names, "gofish")
}
