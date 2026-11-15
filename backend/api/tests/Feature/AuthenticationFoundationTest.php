<?php

namespace Tests\Feature;

use Tests\TestCase;

class AuthenticationFoundationTest extends TestCase
{
    public function test_private_profile_requires_authentication(): void
    {
        $this->getJson('/api/v1/me')
            ->assertUnauthorized();
    }

    public function test_preferences_require_authentication(): void
    {
        $this->getJson('/api/v1/preferences')
            ->assertUnauthorized();

        $this->putJson('/api/v1/preferences/theme', [
            'theme_mode' => 'dark',
        ])->assertUnauthorized();
    }

    public function test_login_requires_valid_input(): void
    {
        $this->postJson('/api/v1/auth/token', [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors([
                'email',
                'password',
                'device_name',
            ]);
    }
}