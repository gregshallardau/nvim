<?php

namespace App\Filament\Resources;

use App\Models\Post;
use App\Filament\Resources\PostResource\Pages\ListPosts;
use Filament\Resources\Resource;
use Filament\Forms\Components\TextInput;

class PostResource extends Resource
{
    protected static ?string $model = Post::class;

    public static function getPages(): array
    {
        return ['index' => ListPosts::route('/')];
    }
}
