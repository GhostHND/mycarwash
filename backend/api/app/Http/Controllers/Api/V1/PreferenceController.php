<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class PreferenceController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $preferences = DB::table('user_preferences')
            ->where('user_id', $request->user()->id)
            ->first();

        return response()->json([
            'theme_mode' => $preferences?->theme_mode ?? 'system',
            'locale' => $preferences?->locale ?? 'es-HN',
        ]);
    }

    public function updateTheme(Request $request): JsonResponse
    {
        $data = $request->validate([
            'theme_mode' => [
                'required',
                Rule::in(['light', 'dark', 'system']),
            ],
        ]);

        $userId = $request->user()->id;
        $now = now();

        DB::table('user_preferences')->upsert(
            [
                [
                    'user_id' => $userId,
                    'theme_mode' => $data['theme_mode'],
                    'locale' => 'es-HN',
                    'created_at' => $now,
                    'updated_at' => $now,
                ],
            ],
            ['user_id'],
            ['theme_mode', 'updated_at']
        );

        return $this->show($request);
    }
}