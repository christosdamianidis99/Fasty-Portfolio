using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Identity;

public sealed class RegistrationUserManager : UserManager<ApplicationUser>
{
    private readonly IOptions<RegistrationOptions> _registrationOptions;

    public RegistrationUserManager(
        IUserStore<ApplicationUser> store,
        IOptions<IdentityOptions> optionsAccessor,
        IPasswordHasher<ApplicationUser> passwordHasher,
        IEnumerable<IUserValidator<ApplicationUser>> userValidators,
        IEnumerable<IPasswordValidator<ApplicationUser>> passwordValidators,
        ILookupNormalizer keyNormalizer,
        IdentityErrorDescriber errors,
        IServiceProvider services,
        ILogger<UserManager<ApplicationUser>> logger,
        IOptions<RegistrationOptions> registrationOptions)
        : base(
            store,
            optionsAccessor,
            passwordHasher,
            userValidators,
            passwordValidators,
            keyNormalizer,
            errors,
            services,
            logger)
    {
        _registrationOptions = registrationOptions;
    }

    public override Task<IdentityResult> CreateAsync(
        ApplicationUser user,
        string password)
    {
        AutoConfirmForBeta(user);

        return base.CreateAsync(user, password);
    }

    public override async Task<bool> CheckPasswordAsync(
        ApplicationUser user,
        string password)
    {
        var passwordIsValid =
            await base.CheckPasswordAsync(user, password);

        if (passwordIsValid
            && !_registrationOptions.Value.RequireEmailVerification
            && !user.EmailConfirmed)
        {
            user.EmailConfirmed = true;

            var updateResult = await UpdateAsync(user);

            if (!updateResult.Succeeded)
            {
                return false;
            }
        }

        return passwordIsValid;
    }

    private void AutoConfirmForBeta(ApplicationUser user)
    {
        if (!_registrationOptions.Value.RequireEmailVerification)
        {
            user.EmailConfirmed = true;
        }
    }
}
